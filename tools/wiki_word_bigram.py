#!/usr/bin/env python3
"""
詞級 bigram pipeline：用 ckip-mlx (MLX fp16) WS-only 斷詞。
~1100 lines/s, 9.1M lines ETA ~2.3 hours.

用法: python3 tools/wiki_word_bigram.py
輸出: data/word_bigram.json
"""
import sys, json, os, time, gc
sys.path.insert(0, os.path.expanduser("~/Python/ckip_mlx"))

import mlx.core as mx
from bert_mlx import BertForTokenClassification
from pathlib import Path
from collections import Counter, defaultdict
from tqdm import tqdm

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
OUT = DATA / "word_bigram.json"
CKPT = DATA / "word_bigram_ckpt.json"
MODEL_DIR = os.path.expanduser("~/Python/ckip_mlx/models")

MIN_FREQ = 10
TOP_K = 5
BATCH_SIZE = 8
MAX_SEQ = 510
CKPT_INTERVAL = 100_000  # save checkpoint every N lines


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
        if s is None:
            continue
        if s >= len(text):
            break
        if preds[i] == 0 and cur:
            words.append(cur)
            cur = text[s]
        else:
            cur += text[s]
    if cur:
        words.append(cur)
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

    print(f"[3/4] MLX 斷詞 + 統計詞級 bigram (batch={BATCH_SIZE})...")
    word_bigram = Counter()
    start_line = 0
    errors = 0

    # Resume from checkpoint
    if CKPT.exists():
        with open(CKPT) as f:
            ckpt = json.load(f)
        start_line = ckpt["line"]
        word_bigram = Counter({tuple(k.split("\t")): v for k, v in ckpt["bigrams"].items()})
        print(f"  ⏩ 續跑: line {start_line:,}, {len(word_bigram):,} bigrams")

    total_batches = (len(lines) - start_line + BATCH_SIZE - 1) // BATCH_SIZE
    pbar = tqdm(total=total_batches, desc="斷詞", unit="batch")

    for i in range(start_line, len(lines), BATCH_SIZE):
        batch = lines[i : i + BATCH_SIZE]

        try:
            ids, masks, spans = tok.encode_batch(batch)
            logits = model(ids, masks)
            preds = mx.argmax(logits, axis=-1).tolist()
            mx.eval(preds)

            for j, text in enumerate(batch):
                words = decode_ws(preds[j], spans[j], text)
                for k in range(len(words) - 1):
                    word_bigram[(words[k], words[k + 1])] += 1
        except Exception as e:
            errors += 1
            if errors <= 5:
                tqdm.write(f"  error at line {i}: {e}")
            # Dynamic batch shrink on OOM-like errors
            gc.collect()

        pbar.update(1)

        # Checkpoint
        processed = i + len(batch)
        if processed % CKPT_INTERVAL < BATCH_SIZE:
            ckpt_data = {
                "line": processed,
                "bigrams": {f"{k[0]}\t{k[1]}": v for k, v in word_bigram.items()},
            }
            with open(CKPT, "w") as f:
                json.dump(ckpt_data, f, ensure_ascii=False)
            tqdm.write(f"  💾 ckpt: {processed:,} lines, {len(word_bigram):,} bigrams")

    pbar.close()
    print(f"  總 bigram: {len(word_bigram):,}, errors: {errors} ({time.time()-t0:.0f}s)")

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

    sz = os.path.getsize(OUT)
    print(f"  {len(result):,} entries, {sz / 1e6:.1f} MB")
    print(f"  完成 ({time.time()-t0:.0f}s)")

    for w in ["研究", "臺灣", "中國", "美國", "大學", "政府", "電影", "音樂", "量子", "共產黨"]:
        print(f"  {w} → {result.get(w, [])}")

    # Cleanup checkpoint
    if CKPT.exists():
        CKPT.unlink()


if __name__ == "__main__":
    main()
