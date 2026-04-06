#!/usr/bin/env python3
"""
Step 1: ckip-mlx 斷詞 → parquet (每 100 萬行一個 shard)
Step 2: 從 parquet 算詞級 n-gram

用法:
  python3 tools/wiki_word_bigram.py ws       # 斷詞 → parquet shards
  python3 tools/wiki_word_bigram.py ngram    # parquet → word_bigram.json
"""
import sys, json, os, time
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


def cmd_ws():
    import mlx.core as mx
    from bert_mlx import BertForTokenClassification
    import pyarrow as pa, pyarrow.parquet as pq
    from tqdm import tqdm

    SHARD_DIR.mkdir(exist_ok=True)

    # Find which shard to resume from
    existing = sorted(SHARD_DIR.glob("shard_*.parquet"))
    start_shard = len(existing)
    start_line = start_shard * SHARD_SIZE
    print(f"已有 {start_shard} shards, 從 line {start_line:,} 續跑")

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
    unk, cls, sep = vocab.get("[UNK]",100), vocab.get("[CLS]",101), vocab.get("[SEP]",102)

    def enc(texts):
        ids, masks, spans = [], [], []
        ml = 0
        for t in texts:
            t = t[:MAX_SEQ]
            d = [cls]+[vocab.get(c,unk) for c in t]+[sep]
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

    # Stream and shard
    t0 = time.time()
    idx = 0
    shard_words = []  # list of "word1\tword2\t..." strings
    shard_num = start_shard

    with open(WIKI, encoding="utf-8") as f:
        batch_buf = []
        pbar = tqdm(desc=f"斷詞 (shard {shard_num})", unit="line")

        for raw in f:
            raw = raw.strip()
            if len(raw) < 4: continue
            if idx < start_line:
                idx += 1; continue
            batch_buf.append(raw)
            idx += 1

            if len(batch_buf) >= BATCH_SIZE:
                try:
                    ids, masks, spans = enc(batch_buf)
                    preds = mx.argmax(model(ids, masks), axis=-1).tolist()
                    for j, text in enumerate(batch_buf):
                        words = decode(preds[j], spans[j], text)
                        if words:
                            shard_words.append("\t".join(words))
                except Exception:
                    pass
                pbar.update(len(batch_buf))
                batch_buf = []

            # Save shard
            if len(shard_words) >= SHARD_SIZE:
                out_path = SHARD_DIR / f"shard_{shard_num:03d}.parquet"
                table = pa.table({"words": shard_words})
                pq.write_table(table, out_path, compression="zstd")
                elapsed = time.time() - t0
                speed = (idx - start_line) / elapsed
                print(f"\n💾 {out_path.name}: {len(shard_words):,} rows, "
                      f"{os.path.getsize(out_path)/1e6:.1f} MB, "
                      f"{speed:.0f} lines/s")
                shard_words = []
                shard_num += 1
                pbar.set_description(f"斷詞 (shard {shard_num})")

        # Final batch
        if batch_buf:
            try:
                ids, masks, spans = enc(batch_buf)
                preds = mx.argmax(model(ids, masks), axis=-1).tolist()
                for j, text in enumerate(batch_buf):
                    words = decode(preds[j], spans[j], text)
                    if words:
                        shard_words.append("\t".join(words))
            except Exception: pass
            pbar.update(len(batch_buf))

        # Final shard
        if shard_words:
            out_path = SHARD_DIR / f"shard_{shard_num:03d}.parquet"
            table = pa.table({"words": shard_words})
            pq.write_table(table, out_path, compression="zstd")
            print(f"\n💾 {out_path.name}: {len(shard_words):,} rows")

        pbar.close()

    elapsed = time.time() - t0
    total_shards = len(list(SHARD_DIR.glob("shard_*.parquet")))
    print(f"\n✅ 斷詞完成: {total_shards} shards, {elapsed/3600:.1f}h")


def cmd_ngram():
    import pyarrow.parquet as pq
    from collections import Counter, defaultdict

    shards = sorted(SHARD_DIR.glob("shard_*.parquet"))
    print(f"讀取 {len(shards)} shards...")

    bg = Counter()
    total = 0
    for sp in shards:
        table = pq.read_table(sp)
        for row in table["words"].to_pylist():
            words = row.split("\t")
            for i in range(len(words) - 1):
                bg[(words[i], words[i+1])] += 1
            total += 1
        print(f"  {sp.name}: +{len(table):,} rows, 累計 bigrams {len(bg):,}")

    print(f"\n總行數: {total:,}, raw bigrams: {len(bg):,}")

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
        print("用法:\n  python3 tools/wiki_word_bigram.py ws     # 斷詞\n  python3 tools/wiki_word_bigram.py ngram  # 算 bigram")
        sys.exit(1)
    if sys.argv[1] == "ws": cmd_ws()
    elif sys.argv[1] == "ngram": cmd_ngram()
    else: print(f"未知指令: {sys.argv[1]}")
