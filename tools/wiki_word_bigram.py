#!/usr/bin/env python3
"""
詞級 bigram pipeline v2：ckip-mlx fp16 WS-only。
修正：checkpoint 只存行號，bigram 用 pickle（快 100x）。
~320 lines/s, 9.1M lines ETA ~8 hours.

用法: python3 tools/wiki_word_bigram.py
"""
import sys, json, os, time, gc, pickle
sys.path.insert(0, os.path.expanduser("~/Python/ckip_mlx"))

import mlx.core as mx
from bert_mlx import BertForTokenClassification
from pathlib import Path
from collections import Counter, defaultdict
from tqdm import tqdm

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
OUT = DATA / "word_bigram.json"
CKPT_LINE = DATA / "word_bigram_ckpt_line.txt"
CKPT_DATA = DATA / "word_bigram_ckpt.pkl"
MODEL_DIR = os.path.expanduser("~/Python/ckip_mlx/models")

MIN_FREQ = 10
TOP_K = 5
BATCH_SIZE = 8
MAX_SEQ = 510
CKPT_INTERVAL = 500_000  # every 500K lines


class WPTokenizer:
    def __init__(self, vocab_path):
        self.vocab = {}
        with open(vocab_path) as f:
            for i, line in enumerate(f):
                self.vocab[line.strip()] = i
        self.unk = self.vocab.get("[UNK]", 100)
        self.cls = self.vocab.get("[CLS]", 101)
        self.sep = self.vocab.get("[SEP]", 102)

    def encode_batch(self, texts):
        all_ids, all_masks, all_spans = [], [], []
        max_len = 0
        for t in texts:
            t = t[:MAX_SEQ]
            ids = [self.cls] + [self.vocab.get(c, self.unk) for c in t] + [self.sep]
            all_ids.append(ids)
            all_masks.append([1] * len(ids))
            all_spans.append([None] + list(range(len(t))) + [None])
            max_len = max(max_len, len(ids))
        for i in range(len(all_ids)):
            pad = max_len - len(all_ids[i])
            all_ids[i] += [0] * pad
            all_masks[i] += [0] * pad
        return mx.array(all_ids), mx.array(all_masks), all_spans


def decode_ws(preds, spans, text):
    words, cur = [], ""
    for i, s in enumerate(spans):
        if s is None: continue
        if s >= len(text): break
        if preds[i] == 0 and cur:
            words.append(cur); cur = text[s]
        else:
            cur += text[s]
    if cur: words.append(cur)
    return [w for w in words if len(w) >= 2]


def main():
    t0 = time.time()

    print("[1/4] 載入 ckip-mlx WS fp16...")
    ws_dir = os.path.join(MODEL_DIR, "ws-fp16")
    with open(os.path.join(ws_dir, "config.json")) as f:
        config = json.load(f)
    config["num_labels"] = 2
    model = BertForTokenClassification(config)
    model.load_weights(os.path.join(ws_dir, "weights.safetensors"))
    mx.eval(model.parameters())
    tok = WPTokenizer(os.path.join(MODEL_DIR, "vocab.txt"))
    print(f"  OK ({time.time()-t0:.1f}s)")

    print("[2/4] 讀取 wiki_clean.txt...")
    lines = []
    with open(WIKI, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if len(line) >= 4:
                lines.append(line)
    print(f"  {len(lines):,} lines ({time.time()-t0:.0f}s)")

    # Resume
    word_bigram = Counter()
    start_line = 0
    if CKPT_LINE.exists() and CKPT_DATA.exists():
        start_line = int(CKPT_LINE.read_text().strip())
        with open(CKPT_DATA, "rb") as f:
            word_bigram = pickle.load(f)
        print(f"  ⏩ 續跑: line {start_line:,}, {len(word_bigram):,} bigrams")

    print(f"[3/4] 斷詞 + 統計 (batch={BATCH_SIZE}, ~320 lines/s)...")
    remaining = len(lines) - start_line
    pbar = tqdm(total=remaining, initial=0, desc="斷詞", unit="line")

    for i in range(start_line, len(lines), BATCH_SIZE):
        batch = lines[i:i+BATCH_SIZE]
        try:
            ids, masks, spans = tok.encode_batch(batch)
            logits = model(ids, masks)
            preds = mx.argmax(logits, axis=-1).tolist()

            for j, text in enumerate(batch):
                words = decode_ws(preds[j], spans[j], text)
                for k in range(len(words) - 1):
                    word_bigram[(words[k], words[k+1])] += 1
        except Exception:
            pass

        pbar.update(len(batch))

        # Checkpoint (pickle, fast)
        processed = i + len(batch)
        if processed % CKPT_INTERVAL < BATCH_SIZE:
            CKPT_LINE.write_text(str(processed))
            with open(CKPT_DATA, "wb") as f:
                pickle.dump(word_bigram, f)
            tqdm.write(f"  💾 ckpt: {processed:,} lines, {len(word_bigram):,} bigrams")

    pbar.close()
    print(f"  完成: {len(word_bigram):,} bigrams ({time.time()-t0:.0f}s)")

    print(f"[4/4] 建 word_bigram.json (freq>={MIN_FREQ}, top {TOP_K})...")
    grouped = defaultdict(list)
    for (w1, w2), freq in word_bigram.items():
        if freq >= MIN_FREQ:
            grouped[w1].append((w2, freq))

    result = {}
    for w, pairs in grouped.items():
        pairs.sort(key=lambda x: x[1], reverse=True)
        result[w] = [w2 for w2, _ in pairs[:TOP_K]]

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"  {len(result):,} entries, {os.path.getsize(OUT)/1e6:.1f} MB")

    for w in ["研究", "臺灣", "中國", "美國", "大學", "政府", "電影", "音樂", "量子", "共產黨"]:
        print(f"  {w} → {result.get(w, [])}")

    # Cleanup
    CKPT_LINE.unlink(missing_ok=True)
    CKPT_DATA.unlink(missing_ok=True)
    print(f"  總耗時: {(time.time()-t0)/3600:.1f} hours")


if __name__ == "__main__":
    main()
