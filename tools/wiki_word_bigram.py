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
from pathlib import Path

# ckip_mlx 模型庫位置：預設 ~/Python/ckip_mlx，可用環境變數 CKIP_MLX_PATH 覆寫
CKIP_MLX = Path(os.environ.get("CKIP_MLX_PATH", os.path.expanduser("~/Python/ckip_mlx")))
sys.path.insert(0, str(CKIP_MLX))

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
SHARD_DIR = DATA / "wiki_ws_shards"
OUT = DATA / "word_bigram.json"
MODEL_DIR = CKIP_MLX / "models"

BATCH_SIZE = 8
MAX_SEQ = 510
SHARD_SIZE = 1_000_000
PARTIAL_SIZE = 100_000


def _atomic_write(path, text):
    """寫到 .tmp 再原子置換，避免中斷留下半個出貨檔。"""
    tmp = str(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def cmd_ws():
    if not CKIP_MLX.is_dir():
        sys.exit(f"❌ 找不到 ckip_mlx 目錄: {CKIP_MLX}（請以環境變數 CKIP_MLX_PATH 指定，內含 models/ 與 bert_mlx）")
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
    # 續跑錨點＝原始檔案行號。shard/partial 只存「有斷出詞」的列（部分輸入行
    # 產不出 ≥2 字詞），無法由過濾後列數回推原始行號，必須靠 checkpoint 對齊，
    # 否則每次續跑都會重複/漏計 n-gram。
    cp_path = SHARD_DIR / "resume_checkpoint.json"
    start_raw_line = 0
    if cp_path.exists():
        with open(cp_path, encoding="utf-8") as f:
            cp = json.load(f)
        if "rows" not in cp or "shards" not in cp:
            sys.exit("❌ resume_checkpoint.json 為舊版格式（缺 rows/shards），無法對齊；請清空 SHARD_DIR 重跑")
        start_raw_line = cp["raw_line"]
        # 崩潰窗口對帳：partial 先寫、checkpoint 後寫，crash 可能留下
        # 比 checkpoint 更多的 partial 列（重複）或更多 shard（merge 完但
        # checkpoint 未更新）。以 checkpoint 為準截斷/校正，否則續跑會重複計數。
        if start_shard > cp["shards"]:
            # merge_shard 已完成但 checkpoint 未寫：merged shard 已涵蓋到
            # raw_line，丟棄殘留 partial（若有），從 raw_line 續跑。
            for p in partials: p.unlink()
            partials, partial_words, partial_lines = [], [], 0
        elif start_shard < cp["shards"]:
            sys.exit("❌ checkpoint 記錄的 shard 數多於磁碟上的 shard（檔案遺失？）；請清空 SHARD_DIR 重跑")
        elif partial_lines > cp["rows"]:
            # partial 寫了但 checkpoint 沒寫到：截斷多出的列並重寫最後一個 partial
            overflow = partial_lines - cp["rows"]
            partial_words = partial_words[:cp["rows"]]
            partial_lines = cp["rows"]
            for p in partials: p.unlink()
            if partial_words:
                pq.write_table(pa.table({"words": partial_words}), SHARD_DIR / "partial_000.parquet")
                partials = [SHARD_DIR / "partial_000.parquet"]
            else:
                partials = []
            print(f"⚠️ 截斷 {overflow:,} 列未 checkpoint 的 partial（crash window）")
        elif partial_lines < cp["rows"]:
            sys.exit("❌ partial 列數少於 checkpoint 記錄（檔案損毀？）；請清空 SHARD_DIR 重跑")
    elif done_shards or partials:
        sys.exit("❌ 發現舊版 shards/partials 但無 resume_checkpoint.json，無法對齊原始行號；請清空 SHARD_DIR 重跑")
    print(f"已有 {start_shard} shards + {len(partials)} partials ({partial_lines:,} rows)")
    print(f"從原始行 {start_raw_line:,} 續跑")

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

    def save_checkpoint(raw_line, rows, shards):
        """記錄已完整處理到的原始行號（不含還在 batch_buf 裡的行），
        連同已落盤的 partial 列數與已完成 shard 數——resume 據此對帳
        崩潰窗口（partial 先寫、checkpoint 後寫）。"""
        tmp = SHARD_DIR / "resume_checkpoint.json.tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"raw_line": raw_line, "rows": rows, "shards": shards}, f)
        os.replace(tmp, SHARD_DIR / "resume_checkpoint.json")

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
    flushed = len(partial_words)  # 已落盤的列數（shard_words 前段已在磁碟上）
    batch_buf = []
    raw_idx = 0        # 原始檔案行號（含被過濾的短行）
    fail_batches = 0
    total_batches = 0

    # Count total
    total_lines = sum(1 for l in open(WIKI) if len(l.strip()) >= 4)
    print(f"總共 {total_lines:,} lines, 從原始行 {start_raw_line:,} 續跑")

    pbar = tqdm(total=total_lines, desc=f"shard {shard_num}", unit="line")

    with open(WIKI, encoding="utf-8") as f:
        for raw in f:
            raw_idx += 1
            if raw_idx <= start_raw_line:
                if len(raw.strip()) >= 4:
                    pbar.update(1)  # 跳過的列也要計入進度條
                continue
            raw = raw.strip()
            if len(raw) < 4: continue
            batch_buf.append(raw)

            if len(batch_buf) >= BATCH_SIZE:
                total_batches += 1
                try:
                    ids_t, masks_t, spans = enc(batch_buf)
                    preds = mx.argmax(model(ids_t, masks_t), axis=-1).tolist()
                    for j, text in enumerate(batch_buf):
                        words = decode(preds[j], spans[j], text)
                        if words:
                            shard_words.append("\t".join(words))
                except Exception as e:
                    fail_batches += 1
                    tqdm.write(f"  ⚠️ 斷詞失敗，丟棄 {len(batch_buf)} 行 "
                               f"({fail_batches}/{total_batches} batches): {e!r}")
                if fail_batches > 100 or (total_batches >= 100 and fail_batches * 100 > total_batches):
                    sys.exit(f"❌ 斷詞失敗率過高 ({fail_batches}/{total_batches} batches)，中止以免靜默丟語料")
                pbar.update(len(batch_buf))
                batch_buf = []

            # Save partial（把尚未落盤的全部列寫成一個 partial，非固定大小：
            # 如此 save 當下所有已解碼列都在磁碟上，checkpoint 的原始行號才精確）
            if len(shard_words) - flushed >= PARTIAL_SIZE:
                chunk = shard_words[flushed:]
                p = save_partial(chunk, partial_idx)
                save_checkpoint(raw_idx - len(batch_buf), len(shard_words), shard_num)
                elapsed = time.time() - t0
                speed = pbar.n / elapsed if elapsed > 0 else 0
                tqdm.write(f"  💾 {p.name}: {len(chunk):,} rows ({speed:.0f} lines/s)")
                flushed = len(shard_words)
                partial_idx += 1

                if interrupted:
                    tqdm.write("⏸ 溫和中斷，partial 已存")
                    pbar.close(); return

            # Shard complete
            if len(shard_words) >= SHARD_SIZE:
                # Save remaining as partial first
                if flushed < len(shard_words):
                    save_partial(shard_words[flushed:], partial_idx)
                    partial_idx += 1
                out, n = merge_shard(shard_num)
                save_checkpoint(raw_idx - len(batch_buf), 0, shard_num + 1)
                flushed = 0
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
        total_batches += 1
        try:
            ids_t, masks_t, spans = enc(batch_buf)
            preds = mx.argmax(model(ids_t, masks_t), axis=-1).tolist()
            for j, text in enumerate(batch_buf):
                words = decode(preds[j], spans[j], text)
                if words: shard_words.append("\t".join(words))
        except Exception as e:
            fail_batches += 1
            tqdm.write(f"  ⚠️ 斷詞失敗，丟棄 {len(batch_buf)} 行 "
                       f"({fail_batches}/{total_batches} batches): {e!r}")
        pbar.update(len(batch_buf))

    if fail_batches:
        tqdm.write(f"⚠️ 共 {fail_batches}/{total_batches} 個批次斷詞失敗，這些行未計入 n-gram")

    if shard_words:
        if flushed < len(shard_words):
            save_partial(shard_words[flushed:], partial_idx)
        out, n = merge_shard(shard_num)
        save_checkpoint(raw_idx, 0, shard_num + 1)  # batch_buf 已清空，全部行都已處理
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

    bg2, bg3, bg4 = Counter(), Counter(), Counter()
    total = 0
    for sp in files:
        for row in pq.read_table(sp)["words"].to_pylist():
            words = row.split("\t")
            n = len(words)
            for i in range(n - 1):
                bg2[(words[i], words[i+1])] += 1
            for i in range(n - 2):
                bg3[(words[i], words[i+1], words[i+2])] += 1
            for i in range(n - 3):
                bg4[(words[i], words[i+1], words[i+2], words[i+3])] += 1
            total += 1
        print(f"  {sp.name}: {total:,} rows | 2g:{len(bg2):,} 3g:{len(bg3):,} 4g:{len(bg4):,}")

    SAMPLES = ["研究", "臺灣", "中國", "美國", "大學", "政府", "電影", "音樂", "量子", "共產黨"]

    for name, counter, n, min_freq in [
        ("word_bigram", bg2, 2, 10),
        ("word_trigram", bg3, 3, 5),
        ("word_4gram", bg4, 4, 3),
    ]:
        grouped = defaultdict(list)
        for key, freq in counter.items():
            if freq >= min_freq:
                grouped[key[:-1]].append((key[-1], freq))
        result = {}
        for ctx, pairs in grouped.items():
            pairs.sort(key=lambda x: x[1], reverse=True)
            k = "\t".join(ctx) if n > 2 else ctx[0]
            result[k] = [w for w, _ in pairs[:5]]
        out = DATA / f"{name}.json"
        _atomic_write(out, json.dumps(result, ensure_ascii=False))
        print(f"\n📦 {name}.json: {len(result):,} entries, {os.path.getsize(out)/1e6:.1f} MB (freq≥{min_freq})")
        for w in SAMPLES:
            if n == 2:
                print(f"  {w} → {result.get(w, [])}")
            else:
                hits = [(k, v) for k, v in result.items() if k.startswith(w)][:3]
                for k, v in hits:
                    print(f"  {k} → {v}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:\n  python3 tools/wiki_word_bigram.py ws\n  python3 tools/wiki_word_bigram.py ngram")
        sys.exit(1)
    {"ws": cmd_ws, "ngram": cmd_ngram}.get(sys.argv[1], lambda: print(f"未知: {sys.argv[1]}"))()
