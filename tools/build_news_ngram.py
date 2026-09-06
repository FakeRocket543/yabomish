#!/usr/bin/env python3
"""Build Chinese news n-gram frequency tables.

Reads a raw Chinese news corpus (one sentence per line).  If a line contains
whitespace it is treated as already word-segmented; otherwise it is tokenised
character by character, keeping only CJK Unified Ideographs and skipping
punctuation.

Outputs:
    news_unigram.csv      -> columns: char,freq
    news_bigram_general.csv -> columns: bigram,freq
    news_trigram_general.csv -> columns: trigram,freq
    news_word_bigram.csv  -> columns: bigram,freq (only if input is segmented)
"""

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path

CHINESE_RE = re.compile(r"[\u4e00-\u9fff]")


def iter_lines(path, encoding="utf-8"):
    with open(path, encoding=encoding, errors="ignore") as f:
        for line in f:
            yield line.rstrip("\r\n")


def is_chinese(c: str) -> bool:
    return "\u4e00" <= c <= "\u9fff"


def tokenize_chars(text: str):
    return [c for c in text if is_chinese(c)]


def segmented_words(line: str):
    return [w for w in line.split() if any(is_chinese(c) for c in w)]


def write_counter(counter: Counter, out_dir: Path, filename: str, key_col: str, top_k: int = 0):
    items = counter.most_common()
    if top_k > 0:
        items = items[:top_k]

    out_path = out_dir / filename
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([key_col, "freq"])
        for k, v in items:
            writer.writerow([k, v])
    return out_path


def main():
    parser = argparse.ArgumentParser(description="Build news n-gram frequency tables.")
    parser.add_argument("--input", default="data/news_corpus.txt", help="Input corpus file.")
    parser.add_argument("--output-dir", default="data", help="Directory for output CSVs.")
    parser.add_argument("--top-k", type=int, default=0, help="Keep only top-K rows per output (0 = all).")
    parser.add_argument("--encoding", default="utf-8", help="Text encoding of the input file.")
    args = parser.parse_args()

    input_path = Path(args.input)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if not input_path.exists():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    unigram = Counter()
    bigram = Counter()
    trigram = Counter()
    word_bigram = Counter()

    total_lines = 0
    segmented_lines = 0

    for line in iter_lines(input_path, args.encoding):
        total_lines += 1

        has_whitespace = bool(re.search(r"\s", line))
        if has_whitespace:
            segmented_lines += 1
            words = segmented_words(line)
            for i in range(len(words) - 1):
                word_bigram[f"{words[i]} {words[i + 1]}"] += 1
            chars = tokenize_chars("".join(words))
        else:
            chars = tokenize_chars(line)

        for ch in chars:
            unigram[ch] += 1
        for i in range(len(chars) - 1):
            bigram[chars[i] + chars[i + 1]] += 1
        for i in range(len(chars) - 2):
            trigram[chars[i] + chars[i + 1] + chars[i + 2]] += 1

    write_counter(unigram, out_dir, "news_unigram.csv", "char", args.top_k)
    write_counter(bigram, out_dir, "news_bigram_general.csv", "bigram", args.top_k)
    write_counter(trigram, out_dir, "news_trigram_general.csv", "trigram", args.top_k)

    if word_bigram:
        write_counter(word_bigram, out_dir, "news_word_bigram.csv", "bigram", args.top_k)

    print(f"Processed {total_lines} lines ({segmented_lines} segmented).")
    print(f"  char unigrams:  {len(unigram)}")
    print(f"  char bigrams:   {len(bigram)}")
    print(f"  char trigrams:  {len(trigram)}")
    if word_bigram:
        print(f"  word bigrams:   {len(word_bigram)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
