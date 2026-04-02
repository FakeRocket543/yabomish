#!/usr/bin/env python3
"""
從萌典資料切割一般字/破音字，結合字頻排序，輸出 CSV + Parquet。

資料架構：
├── 一般字（單音字）: 1-gram 字頻
├── 破音字（多音字）: 每個讀音各自的字頻（以萌典第一音為主音，其餘降權）
├── 2-gram / 3-gram: 從注音→字對照表建立候選詞組頻率骨架
└── 所有資料輸出為 CSV + Parquet
"""
import json, os, sys
from collections import defaultdict
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"
OUT = BASE / "data"

POLY_DISCOUNT = 0.3  # 非主音的字頻折扣係數


def load_data():
    with open(RES / "zhuyin_data.json", encoding="utf-8") as f:
        zy = json.load(f)
    with open(RES / "char_freq.json", encoding="utf-8") as f:
        freq = json.load(f)
    return zy["zhuyin_to_chars"], zy["char_to_zhuyins"], freq


def build_single_and_poly(c2z, freq):
    """切割單音字與破音字，回傳兩個 DataFrame。"""
    single_rows = []
    poly_rows = []

    for char, zhuyins in c2z.items():
        f = freq.get(char, 0)
        if len(zhuyins) == 1:
            single_rows.append({
                "char": char,
                "zhuyin": zhuyins[0],
                "freq": f,
            })
        else:
            primary = zhuyins[0]
            for i, zy in enumerate(zhuyins):
                is_primary = (i == 0)
                effective_freq = f if is_primary else int(f * POLY_DISCOUNT)
                poly_rows.append({
                    "char": char,
                    "zhuyin": zy,
                    "raw_freq": f,
                    "effective_freq": effective_freq,
                    "is_primary": is_primary,
                    "reading_index": i,
                    "total_readings": len(zhuyins),
                })

    df_single = pd.DataFrame(single_rows).sort_values("freq", ascending=False).reset_index(drop=True)
    df_poly = pd.DataFrame(poly_rows).sort_values(
        ["char", "effective_freq"], ascending=[True, False]
    ).reset_index(drop=True)

    return df_single, df_poly


def build_zhuyin_candidates(z2c, c2z, freq):
    """
    為每個注音建立候選字排序表。
    - 單音字：直接用字頻
    - 破音字：主音用原始字頻，非主音打折
    """
    rows = []
    for zy, chars in z2c.items():
        for char in chars:
            f = freq.get(char, 0)
            readings = c2z.get(char, [])
            is_poly = len(readings) > 1
            if is_poly:
                is_primary = (readings[0] == zy) if readings else False
                eff = f if is_primary else int(f * POLY_DISCOUNT)
            else:
                is_primary = True
                eff = f
            rows.append({
                "zhuyin": zy,
                "char": char,
                "raw_freq": f,
                "effective_freq": eff,
                "is_poly": is_poly,
                "is_primary_reading": is_primary,
            })

    df = pd.DataFrame(rows)
    df = df.sort_values(["zhuyin", "effective_freq"], ascending=[True, False]).reset_index(drop=True)
    return df


def build_ngrams(z2c, c2z, freq):
    """
    為每個注音的 top 候選字，建立同注音內的 2-gram 骨架。
    策略：每個注音取 top-5 高頻字，只對「相鄰注音」做組合（此處用全注音 top-50）。
    分開產出一般 n-gram 和破音字 n-gram。
    """
    # 建立每個注音的 top 候選（帶 effective_freq）
    def eff(char, zy):
        f = freq.get(char, 0)
        r = c2z.get(char, [])
        if len(r) > 1 and r[0] != zy:
            return int(f * POLY_DISCOUNT)
        return f

    top_zy = sorted(z2c.keys(), key=lambda k: sum(freq.get(c, 0) for c in z2c[k][:5]), reverse=True)[:80]

    bigram_rows = []
    bigram_poly_rows = []
    seen = set()

    for zy1 in top_zy:
        top1 = sorted(z2c[zy1][:20], key=lambda c: eff(c, zy1), reverse=True)[:5]
        for zy2 in top_zy:
            top2 = sorted(z2c[zy2][:20], key=lambda c: eff(c, zy2), reverse=True)[:5]
            for c1 in top1:
                e1 = eff(c1, zy1)
                if e1 == 0:
                    continue
                r1 = c2z.get(c1, [])
                is_poly1 = len(r1) > 1
                is_primary1 = (r1[0] == zy1) if r1 else True

                for c2 in top2:
                    key = (c1, zy1, c2, zy2)
                    if key in seen:
                        continue
                    seen.add(key)

                    e2 = eff(c2, zy2)
                    if e2 == 0:
                        continue
                    r2 = c2z.get(c2, [])
                    is_poly2 = len(r2) > 1
                    is_primary2 = (r2[0] == zy2) if r2 else True

                    score = e1 * e2
                    has_poly = is_poly1 or is_poly2
                    row = {
                        "bigram": c1 + c2,
                        "zhuyin_1": zy1,
                        "zhuyin_2": zy2,
                        "char_1": c1,
                        "char_2": c2,
                        "score": score,
                    }
                    if has_poly:
                        row["poly_char_1"] = is_poly1
                        row["poly_char_2"] = is_poly2
                        row["primary_1"] = is_primary1
                        row["primary_2"] = is_primary2
                        bigram_poly_rows.append(row)
                    else:
                        bigram_rows.append(row)

    df_bigram = pd.DataFrame(bigram_rows)
    df_bigram_poly = pd.DataFrame(bigram_poly_rows)

    if not df_bigram.empty:
        df_bigram = df_bigram.sort_values("score", ascending=False).reset_index(drop=True)
    if not df_bigram_poly.empty:
        df_bigram_poly = df_bigram_poly.sort_values("score", ascending=False).reset_index(drop=True)

    return df_bigram, df_bigram_poly


def save(df, name):
    OUT.mkdir(exist_ok=True)
    csv_path = OUT / f"{name}.csv"
    pq_path = OUT / f"{name}.parquet"
    df.to_csv(csv_path, index=False, encoding="utf-8-sig")
    df.to_parquet(pq_path, index=False)
    print(f"  {name}: {len(df)} rows → {csv_path.name}, {pq_path.name}")


def main():
    print("載入萌典資料...")
    z2c, c2z, freq = load_data()
    print(f"  注音數: {len(z2c)}, 字數: {len(c2z)}, 字頻表: {len(freq)}")

    print("\n[1] 切割單音字 / 破音字...")
    df_single, df_poly = build_single_and_poly(c2z, freq)
    save(df_single, "single_char_freq")
    save(df_poly, "poly_char_freq")

    print("\n[2] 建立注音候選字排序表...")
    df_candidates = build_zhuyin_candidates(z2c, c2z, freq)
    save(df_candidates, "zhuyin_candidates")

    print("\n[3] 建立 2-gram 骨架（一般 + 破音字）...")
    df_bi, df_bi_poly = build_ngrams(z2c, c2z, freq)
    save(df_bi, "bigram_general")
    save(df_bi_poly, "bigram_poly")

    # 統計摘要
    print("\n=== 摘要 ===")
    print(f"單音字: {len(df_single)}")
    print(f"破音字: {len(df_poly)} (涵蓋 {df_poly['char'].nunique()} 個字)")
    print(f"注音候選表: {len(df_candidates)} (涵蓋 {df_candidates['zhuyin'].nunique()} 個注音)")
    print(f"一般 2-gram: {len(df_bi)}")
    print(f"破音字 2-gram: {len(df_bi_poly)}")

    # 輸出前幾筆供驗證
    print("\n--- 單音字 Top 10 ---")
    print(df_single.head(10).to_string(index=False))
    print("\n--- 破音字 Top 10 (by raw_freq) ---")
    top_poly = df_poly.drop_duplicates("char").head(10)
    print(top_poly.to_string(index=False))
    print("\n--- 注音 ㄌㄜˋ 候選排序 ---")
    le4 = df_candidates[df_candidates["zhuyin"] == "ㄌㄜˋ"]
    print(le4.to_string(index=False))

    print(f"\n✅ 所有檔案已輸出至 {OUT}/")


if __name__ == "__main__":
    main()
