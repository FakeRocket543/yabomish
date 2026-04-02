#!/usr/bin/env python3
"""
維基中文語料 → ckip 斷詞 → n-gram 統計 pipeline

步驟：
1. 下載 zhwiki dump (bz2)
2. WikiExtractor 抽純文字
3. OpenCC 繁體轉換
4. ckip 斷詞
5. 統計 1/2/3-gram（一般字 vs 破音字分開）
6. 輸出 CSV + Parquet

用法：
  python3 tools/wiki_ngram_pipeline.py              # 全部跑
  python3 tools/wiki_ngram_pipeline.py --skip-download  # 跳過下載（已有 dump）
  python3 tools/wiki_ngram_pipeline.py --from-extract   # 從抽文字開始
  python3 tools/wiki_ngram_pipeline.py --from-segment   # 從斷詞結果開始統計
"""
import argparse, json, os, re, subprocess, sys, glob as globmod
from collections import Counter
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"
WORK = BASE / "data" / "wiki_work"
OUT = BASE / "data"

DUMP_URL = "https://dumps.wikimedia.org/zhwiki/latest/zhwiki-latest-pages-articles.xml.bz2"
DUMP_FILE = WORK / "zhwiki-latest-pages-articles.xml.bz2"
EXTRACT_DIR = WORK / "extracted"
CLEAN_FILE = WORK / "wiki_clean.txt"
SEG_FILE = WORK / "wiki_segmented.txt"

BATCH_SIZE = 64
MAX_LEN = 512


def step_download():
    WORK.mkdir(parents=True, exist_ok=True)
    if DUMP_FILE.exists():
        print(f"  dump 已存在: {DUMP_FILE} ({DUMP_FILE.stat().st_size / 1e9:.1f}GB)")
        return
    print(f"  下載中... {DUMP_URL}")
    subprocess.run(["curl", "-L", "-o", str(DUMP_FILE), DUMP_URL], check=True)
    print(f"  完成: {DUMP_FILE.stat().st_size / 1e9:.1f}GB")


def step_extract():
    if CLEAN_FILE.exists():
        print(f"  純文字已存在: {CLEAN_FILE}")
        return

    try:
        import opencc
        cc = opencc.OpenCC("s2tw")
    except ImportError:
        print("  ⚠️  opencc-python-reimplemented 未安裝，嘗試安裝...")
        subprocess.run([sys.executable, "-m", "pip", "install", "--break-system-packages",
                        "opencc-python-reimplemented"], check=True)
        import opencc
        cc = opencc.OpenCC("s2tw")

    import bz2
    from xml.etree.ElementTree import iterparse

    print("  解析 bz2 XML + 抽文字 + 繁轉...")
    tag_re = re.compile(r"<[^>]+>")
    markup_re = re.compile(r"\{\{[^}]*\}\}|\[\[(?:[^|\]]*\|)?([^\]]*)\]\]|'{2,3}")
    ref_re = re.compile(r"<ref[^>]*>.*?</ref>|<ref[^/]*/?>|</?[a-z][^>]*>", re.S)
    ns = "{http://www.mediawiki.org/xml/export-0.11/}"
    count = 0
    articles = 0

    with bz2.open(str(DUMP_FILE), "rt", encoding="utf-8") as bz, \
         open(CLEAN_FILE, "w", encoding="utf-8") as out:
        for event, elem in iterparse(bz, events=("end",)):
            if elem.tag != f"{ns}text":
                continue
            text = elem.text
            elem.clear()
            if not text:
                continue
            # 跳過重定向
            if text.strip().startswith("#") or text.strip().lower().startswith("#redirect"):
                continue
            articles += 1
            # 清理 wiki markup
            text = ref_re.sub("", text)
            text = markup_re.sub(r"\1", text)
            for line in text.split("\n"):
                line = line.strip()
                if not line or line.startswith(("=", "{", "|", "!", "*", "#", "[")):
                    continue
                line = tag_re.sub("", line).strip()
                if not line:
                    continue
                line = cc.convert(line)
                if re.search(r"[\u4e00-\u9fff]", line):
                    out.write(line + "\n")
                    count += 1
            if articles % 10000 == 0:
                print(f"    {articles} articles, {count} lines...")

    print(f"  完成: {articles} articles, {count} lines → {CLEAN_FILE}")


def step_segment():
    if SEG_FILE.exists():
        print(f"  斷詞結果已存在: {SEG_FILE}")
        return

    print("  載入 ckip_mlx...")
    import sys as _sys
    CKIP_MLX = Path("/Users/fl/Python/ckip_mlx")
    _sys.path.insert(0, str(CKIP_MLX))
    import mlx.core as mx
    from bert_mlx import BertForTokenClassification

    ws_dir = CKIP_MLX / "models" / "ws"
    with open(ws_dir / "config.json") as f:
        config = json.load(f)
    config["num_labels"] = 2
    model = BertForTokenClassification(config)
    model.load_weights(str(ws_dir / "weights.safetensors"))
    mx.eval(model.parameters())

    vocab = {}
    with open(ws_dir / "vocab.txt") as f:
        for i, line in enumerate(f):
            vocab[line.strip()] = i
    unk_id = vocab.get("[UNK]", 100)

    def segment_batch(texts):
        max_len = max(len(t) for t in texts) + 2
        batch_ids, batch_mask = [], []
        for t in texts:
            ids = [101] + [vocab.get(ch, unk_id) for ch in t] + [102]
            pad = max_len - len(ids)
            batch_ids.append(ids + [0] * pad)
            batch_mask.append([1] * len(ids) + [0] * pad)
        out = model(mx.array(batch_ids), attention_mask=mx.array(batch_mask))
        mx.eval(out)
        preds_batch = mx.argmax(out, axis=-1).tolist()
        results = []
        for idx, t in enumerate(texts):
            preds = preds_batch[idx]
            words, cur = [], ""
            for i, ch in enumerate(t):
                if preds[i + 1] == 0 and cur:
                    words.append(cur)
                    cur = ch
                else:
                    cur += ch
            if cur:
                words.append(cur)
            results.append(words)
        return results

    # 讀取 + 切段
    segments = []
    with open(CLEAN_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                for i in range(0, len(line), MAX_LEN):
                    seg = line[i:i + MAX_LEN]
                    if seg:
                        segments.append(seg)

    total = len(segments)
    print(f"  共 {total:,} 段, batch_size={BATCH_SIZE}")

    # warmup
    segment_batch(segments[:2])

    import time
    t0 = time.time()
    with open(SEG_FILE, "w", encoding="utf-8") as out:
        for i in range(0, total, BATCH_SIZE):
            batch = segments[i:i + BATCH_SIZE]
            results = segment_batch(batch)
            for tokens in results:
                out.write(" ".join(tokens) + "\n")
            done = min(i + BATCH_SIZE, total)
            if done % 10000 < BATCH_SIZE:
                elapsed = time.time() - t0
                speed = done / elapsed
                eta = (total - done) / speed
                print(f"    {done:,}/{total:,} ({done * 100 // total}%) "
                      f"{speed:.0f} seg/s, ETA {eta / 60:.0f}min")

    elapsed = time.time() - t0
    print(f"  完成: {SEG_FILE} ({elapsed / 60:.1f}min, {total / elapsed:.0f} seg/s)")


def step_ngram():
    print("  載入萌典資料...")
    with open(RES / "zhuyin_data.json", encoding="utf-8") as f:
        zy = json.load(f)
    with open(RES / "char_freq.json", encoding="utf-8") as f:
        moe_freq = json.load(f)
    c2z = zy["char_to_zhuyins"]
    poly_chars = {c for c, zs in c2z.items() if len(zs) > 1}

    print("  統計 n-gram...")
    uni = Counter()       # 字 unigram
    bi = Counter()        # 一般 bigram
    bi_poly = Counter()   # 破音字 bigram
    tri = Counter()       # 一般 trigram
    tri_poly = Counter()  # 破音字 trigram
    line_count = 0

    with open(SEG_FILE, encoding="utf-8") as f:
        for line in f:
            tokens = line.strip().split()
            # 展開成字序列（只取中文字）
            chars = []
            for tok in tokens:
                for ch in tok:
                    if "\u4e00" <= ch <= "\u9fff" or ch in c2z:
                        chars.append(ch)

            for ch in chars:
                uni[ch] += 1

            for i in range(len(chars) - 1):
                pair = chars[i] + chars[i + 1]
                has_poly = chars[i] in poly_chars or chars[i + 1] in poly_chars
                if has_poly:
                    bi_poly[pair] += 1
                else:
                    bi[pair] += 1

            for i in range(len(chars) - 2):
                trip = chars[i] + chars[i + 1] + chars[i + 2]
                has_poly = any(c in poly_chars for c in trip)
                if has_poly:
                    tri_poly[trip] += 1
                else:
                    tri[trip] += 1

            line_count += 1
            if line_count % 500000 == 0:
                print(f"    {line_count} lines...")

    print(f"  統計完成: {line_count} lines")
    print(f"    unigram: {len(uni)}")
    print(f"    bigram 一般: {len(bi)}, 破音字: {len(bi_poly)}")
    print(f"    trigram 一般: {len(tri)}, 破音字: {len(tri_poly)}")

    # 輸出
    def counter_to_df(ctr, col_name):
        rows = [{"ngram": k, "freq": v} for k, v in ctr.most_common()]
        return pd.DataFrame(rows).rename(columns={"ngram": col_name})

    def save(df, name):
        df.to_csv(OUT / f"{name}.csv", index=False, encoding="utf-8-sig")
        df.to_parquet(OUT / f"{name}.parquet", index=False)
        print(f"    {name}: {len(df)} rows")

    save(counter_to_df(uni, "char"), "wiki_unigram")
    save(counter_to_df(bi, "bigram"), "wiki_bigram_general")
    save(counter_to_df(bi_poly, "bigram"), "wiki_bigram_poly")
    save(counter_to_df(tri, "trigram"), "wiki_trigram_general")
    save(counter_to_df(tri_poly, "trigram"), "wiki_trigram_poly")

    # 額外：用維基 unigram 更新候選排序
    print("\n  用維基字頻重建候選排序表...")
    wiki_freq = dict(uni.most_common())
    rebuild_candidates(zy, c2z, wiki_freq, poly_chars)


def rebuild_candidates(zy, c2z, wiki_freq, poly_chars):
    """用維基字頻重建注音候選排序，取代萌典字頻。"""
    z2c = zy["zhuyin_to_chars"]
    POLY_DISCOUNT = 0.3
    rows = []
    for zy_key, chars in z2c.items():
        for char in chars:
            f = wiki_freq.get(char, 0)
            readings = c2z.get(char, [])
            is_poly = char in poly_chars
            if is_poly:
                is_primary = (readings[0] == zy_key) if readings else False
                eff = f if is_primary else int(f * POLY_DISCOUNT)
            else:
                is_primary = True
                eff = f
            rows.append({
                "zhuyin": zy_key,
                "char": char,
                "wiki_freq": f,
                "effective_freq": eff,
                "is_poly": is_poly,
                "is_primary_reading": is_primary,
            })

    df = pd.DataFrame(rows)
    df = df.sort_values(["zhuyin", "effective_freq"], ascending=[True, False]).reset_index(drop=True)
    df.to_csv(OUT / "wiki_zhuyin_candidates.csv", index=False, encoding="utf-8-sig")
    df.to_parquet(OUT / "wiki_zhuyin_candidates.parquet", index=False)
    print(f"    wiki_zhuyin_candidates: {len(df)} rows")

    # 驗證幾個注音
    for test in ["ㄌㄜˋ", "ㄏㄤˊ", "ㄔㄤˊ"]:
        sub = df[df["zhuyin"] == test].head(6)
        print(f"\n    {test}:")
        print(sub[["char", "wiki_freq", "effective_freq", "is_poly", "is_primary_reading"]].to_string(index=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--from-extract", action="store_true")
    parser.add_argument("--from-segment", action="store_true")
    args = parser.parse_args()

    if not args.from_extract and not args.from_segment:
        print("[1/4] 下載維基中文 dump...")
        if args.skip_download:
            print("  跳過")
        else:
            step_download()

    if not args.from_segment:
        if not args.from_extract:
            print("\n[2/4] 抽取純文字 + 繁體轉換...")
        else:
            print("[2/4] 抽取純文字 + 繁體轉換...")
        step_extract()

        print("\n[3/4] ckip 斷詞...")
        step_segment()

    print("\n[4/4] 統計 n-gram...")
    step_ngram()

    print("\n✅ 全部完成！")


if __name__ == "__main__":
    main()
