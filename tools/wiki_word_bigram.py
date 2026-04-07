#!/usr/bin/env python3
"""
詞級 bigram pipeline v4：
  ws:    斷詞 → parquet shards (每 100 萬行), 內部每 10 萬行存 partial
  ngram: parquet → word_bigram.json

用法:
  python3 tools/wiki_word_bigram.py ws
  python3 tools/wiki_word_bigram.py ngram
"""
import sys, json, os, time, signal
sys.path.insert(0, os.path.expanduser("~/Python/ckip_mlx"))
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
SHARD_DIR = DATA / "wiki_ws_shards"
OUT = DATA / "word_bigram.json"
MODEL_DIR = os.path.expanduser("~/Python/ckip_mlx/models")

BATCH_SIZE = 8
MAX_SEQ = 510
SHARD_SIZE = 1_000_000
PARTIAL_SIZE = 100_000


def cmd_ws():
    import mlx.core as mx
    from bert_mlx import BertForTokenClassification
    import pyarrow as pa, pyarrow.parquet as pq
    from tqdm import tqdm

    SHARD_DIR.mkdir(exist_ok=True)
    interrupted = False
    def on_sigint(sig, frame):
        nonlocal interrupted
        interrupted = True
        print("\n⏸ 收到中斷，存完當前 partial 後停止...")
    signal.signal(signal.SIGINT, on_sigint)

    # Resume: count completed shards + check partial
    done_shards = sorted(SHARD_DIR.glob("shard_*.parquet"))
    partials = sorted(SHARD_DIR.glob("partial_*.parquet"))
    start_shard = len(done_shards)
    # Count lines in partials (belong to current incomplete shard)
    partial_words = []
    for p in partials:
        t = pq.read_table(p)
        partial_words.extend(t["words"].to_pylist())
    partial_lines = len(partial_words)
    start_line = start_shard * SHARD_SIZE + partial_lines
    print(f"已有 {start_shard} shards + {len(partials)} partials ({partial_lines:,} lines)")
    print(f"從 line {start_line:,} 續跑")

    # Load model
    ws_dir = os.path.join(MODEL_DIR, "ws-fp16")
    with open(os.path.join(ws_dir, "config.json")) as f: cfg = json.load(f)
    cfg["num_labels"] = 2
    model = BertForTokenClassification(cfg)
    model.load_weights(os.path.join(ws_dir, "weights.safetensors"))
    mx.eval(model.parameters())

    vocab = {}
    with open(os.path.join(MODEL_DIR, "vocab.txt")) as f:
        for i, l in enumerate(f): vocab[l.strip()] = i
    unk, cls_id, sep_id = vocab.get("[UNK]",100), vocab.get("[CLS]",101), vocab.get("[SEP]",102)

    def enc(texts):
        ids, masks, spans = [], [], []
        ml = 0
        for t in texts:
            t = t[:MAX_SEQ]
            d = [cls_id]+[vocab.get(c,unk) for c in t]+[sep_id]
            ids.append(d); masks.append([1]*len(d))
            spans.append([None]+list(range(len(t)))+[None])
            ml = max(ml, len(d))
        for i in range(len(ids)):
            p = ml-len(ids[i]); ids[i]+=[0]*p; masks[i]+=[0]*p
        return mx.array(ids), mx.array(masks), spans

    def decode(preds, spans, text):
        words, cur = [], ""
        for i, s in enumerate(spans):
            if s is None: continue
            if s >= len(text): break
            if preds[i] == 0 and cur: words.append(cur); cur = text[s]
            else: cur += text[s]
        if cur: words.append(cur)
        return [w for w in words if len(w) >= 2]

    def save_partial(words_list, idx):
        path = SHARD_DIR / f"partial_{idx:03d}.parquet"
        pq.write_table(pa.table({"words": words_list}), path)
        return path

    def merge_shard(shard_num):
        """Merge all partials into one shard, delete partials."""
        parts = sorted(SHARD_DIR.glob("partial_*.parquet"))
        all_words = []
        for p in parts:
            all_words.extend(pq.read_table(p)["words"].to_pylist())
        out = SHARD_DIR / f"shard_{shard_num:03d}.parquet"
        pq.write_table(pa.table({"words": all_words}), out)
        for p in parts: p.unlink()
        return out, len(all_words)

    t0 = time.time()
    shard_num = start_shard
    shard_words = list(partial_words)  # resume partial data
    partial_idx = len(partials)
    batch_buf = []
    idx = 0

    # Count total
    total_lines = sum(1 for l in open(WIKI) if len(l.strip()) >= 4)
    remaining = total_lines - start_line
    print(f"總共 {total_lines:,} lines, 本次處理 {remaining:,}, 預估 {remaining/200/60:.0f} 分鐘")

    pbar = tqdm(total=remaining, desc=f"shard {shard_num}", unit="line")

    with open(WIKI, encoding="utf-8") as f:
        for raw in f:
            raw = raw.strip()
            if len(raw) < 4: continue
            if idx < start_line:
                idx += 1; continue
            batch_buf.append(raw)
            idx += 1

            if len(batch_buf) >= BATCH_SIZE:
                try:
                    ids_t, masks_t, spans = enc(batch_buf)
                    preds = mx.argmax(model(ids_t, masks_t), axis=-1).tolist()
                    for j, text in enumerate(batch_buf):
                        words = decode(preds[j], spans[j], text)
                        if words:
                            shard_words.append("\t".join(words))
                except Exception: pass
                pbar.update(len(batch_buf))
                batch_buf = []

            # Save partial
            if len(shard_words) >= (partial_idx + 1) * PARTIAL_SIZE:
                start_i = partial_idx * PARTIAL_SIZE
                chunk = shard_words[start_i:start_i + PARTIAL_SIZE]
                p = save_partial(chunk, partial_idx)
                elapsed = time.time() - t0
                speed = (idx - start_line) / elapsed if elapsed > 0 else 0
                tqdm.write(f"  💾 {p.name}: {len(chunk):,} rows ({speed:.0f} lines/s)")
                partial_idx += 1

                if interrupted:
                    tqdm.write("⏸ 溫和中斷，partial 已存")
                    pbar.close(); return

            # Shard complete
            if len(shard_words) >= SHARD_SIZE:
                # Save remaining as partial first
                start_i = partial_idx * PARTIAL_SIZE
                if start_i < len(shard_words):
                    save_partial(shard_words[start_i:], partial_idx)
                out, n = merge_shard(shard_num)
                elapsed = time.time() - t0
                tqdm.write(f"\n✅ {out.name}: {n:,} rows, {os.path.getsize(out)/1e6:.1f} MB ({elapsed/60:.0f}min)")
                shard_words = []
                shard_num += 1
                partial_idx = 0
                pbar.set_description(f"shard {shard_num}")

                if interrupted:
                    tqdm.write("⏸ 溫和中斷，shard 已存")
                    pbar.close(); return

    # Final flush
    if batch_buf:
        try:
            ids_t, masks_t, spans = enc(batch_buf)
            preds = mx.argmax(model(ids_t, masks_t), axis=-1).tolist()
            for j, text in enumerate(batch_buf):
                words = decode(preds[j], spans[j], text)
                if words: shard_words.append("\t".join(words))
        except Exception: pass
        pbar.update(len(batch_buf))

    if shard_words:
        start_i = partial_idx * PARTIAL_SIZE
        if start_i < len(shard_words):
            save_partial(shard_words[start_i:], partial_idx)
        out, n = merge_shard(shard_num)
        tqdm.write(f"\n✅ {out.name}: {n:,} rows, {os.path.getsize(out)/1e6:.1f} MB")

    pbar.close()
    total_shards = len(list(SHARD_DIR.glob("shard_*.parquet")))
    print(f"\n🎉 斷詞完成: {total_shards} shards, {(time.time()-t0)/3600:.1f}h")
    print(f"下一步: python3 tools/wiki_word_bigram.py ngram")


def cmd_ngram():
    import pyarrow.parquet as pq
    from collections import Counter, defaultdict

    shards = sorted(SHARD_DIR.glob("shard_*.parquet"))
    partials = sorted(SHARD_DIR.glob("partial_*.parquet"))
    files = shards + partials
    print(f"讀取 {len(shards)} shards + {len(partials)} partials...")

    bg = Counter()
    total = 0
    for sp in files:
        for row in pq.read_table(sp)["words"].to_pylist():
            words = row.split("\t")
            for i in range(len(words) - 1):
                bg[(words[i], words[i+1])] += 1
            total += 1
        print(f"  {sp.name}: 累計 {total:,} rows, {len(bg):,} bigrams")

    MIN_FREQ, TOP_K = 10, 5
    grouped = defaultdict(list)
    for (w1, w2), freq in bg.items():
        if freq >= MIN_FREQ: grouped[w1].append((w2, freq))
    result = {}
    for w, pairs in grouped.items():
        pairs.sort(key=lambda x: x[1], reverse=True)
        result[w] = [w2 for w2, _ in pairs[:TOP_K]]

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"\n📦 word_bigram.json: {len(result):,} entries, {os.path.getsize(OUT)/1e6:.1f} MB")
    for w in ["研究", "臺灣", "中國", "美國", "大學", "政府", "電影", "音樂", "量子", "共產黨"]:
        print(f"  {w} → {result.get(w, [])}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:\n  python3 tools/wiki_word_bigram.py ws\n  python3 tools/wiki_word_bigram.py ngram")
        sys.exit(1)
    {"ws": cmd_ws, "ngram": cmd_ngram}.get(sys.argv[1], lambda: print(f"未知: {sys.argv[1]}"))()
