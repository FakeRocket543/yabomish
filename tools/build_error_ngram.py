#!/usr/bin/env python3
"""Build error-driven n-gram boost CSVs from a typing error log.

Input: data/typing_log.csv with columns mode,expected,actual,context
 mode: 'zhuyin' or 'boshiamy'
 expected: intended code string
 actual: typed code string
 context: optional surrounding Chinese text (used for zhuyin char mapping)

Output:
  data/error_bigram_boost.csv
  data/error_trigram_boost.csv

For each typing error row, difflib.SequenceMatcher is used to locate
insertions, deletions, and substitutions.  N-gram windows around every
mismatch are collected and counted with collections.Counter.
"""

import argparse
import csv
import difflib
from collections import Counter
from pathlib import Path
import sys


def build_actual_to_expected(expected, actual):
    """Return a list mapping each actual index to an expected index.

    Inserted characters map to the nearest expected index (the insertion
    point), because they do not have a real counterpart in the expected
    string.
    """
    a2e = [None] * len(actual)
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, expected, actual).get_opcodes():
        if tag in ("equal", "replace"):
            for a in range(j1, j2):
                a2e[a] = i1 + (a - j1)
        elif tag == "insert":
            # All inserted characters share the expected insertion point.
            # Prefer the next character, fall back to the previous one.
            anchor = i1
            if anchor >= len(expected) and anchor > 0:
                anchor -= 1
            for a in range(j1, j2):
                a2e[a] = anchor
    return a2e


def get_char(t, source, char_indices, mode, context):
    """Return the display label for source position t."""
    if mode == "boshiamy":
        return source[t]
    exp_i = char_indices[t]
    if exp_i is not None and 0 <= exp_i < len(context):
        return context[exp_i]
    return source[t]


def collect_window_ngrams(source, char_indices, err_start, err_end, window, n, mode, context):
    """Yield (zy_tuple, char_tuple) n-grams around an error region."""
    n = int(n)
    if n < 2:
        return
    n_len = len(source)
    left = max(0, err_start - window)
    right = min(n_len, err_end + window)
    if right - left < n:
        return

    seen = set()
    for start in range(left, right - n + 1):
        span = list(range(start, start + n))
        if not any(err_start <= k < err_end for k in span):
            continue
        zys = tuple(source[k] for k in span)
        chars = tuple(get_char(k, source, char_indices, mode, context) for k in span)
        key = (zys, chars)
        if key in seen:
            continue
        seen.add(key)
        yield key


def process_row(row, bi_counter, tri_counter, window):
    mode = row.get("mode", "").strip().lower()
    if mode not in ("zhuyin", "boshiamy"):
        return
    expected = row.get("expected", "")
    actual = row.get("actual", "")
    context = row.get("context", "") or ""
    if expected == actual:
        return

    a2e = build_actual_to_expected(expected, actual)
    sm = difflib.SequenceMatcher(None, expected, actual)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue

        if tag == "delete":
            # Missing code in actual: use expected as the source so the
            # missing code itself can be n-grammed.
            source = list(expected)
            char_indices = list(range(len(source)))
            err_start, err_end = i1, i2
        else:
            # insert or replace: use the actual typed code as the source.
            source = list(actual)
            char_indices = [a2e[k] for k in range(len(source))]
            err_start, err_end = j1, j2

        for zys, chars in collect_window_ngrams(source, char_indices, err_start, err_end, window, 2, mode, context):
            bigram = "".join(chars)
            bi_counter[(zys[0], zys[1], chars[0], chars[1], bigram, mode)] += 1

        for zys, chars in collect_window_ngrams(source, char_indices, err_start, err_end, window, 3, mode, context):
            trigram = "".join(chars)
            tri_counter[(zys[0], zys[1], zys[2], chars[0], chars[1], chars[2], trigram, mode)] += 1


def write_bigram_csv(path, counter):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["prev_zy", "cur_zy", "prev_char", "cur_char", "bigram", "freq", "error_count", "source"])
        for (pzy, czy, pc, cc, bigram, source), freq in counter.most_common():
            w.writerow([pzy, czy, pc, cc, bigram, freq, freq, source])


def write_trigram_csv(path, counter):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["prev_zy", "cur_zy", "next_zy", "prev_char", "cur_char", "next_char", "trigram", "freq", "error_count", "source"])
        for (pzy, czy, nzy, pc, cc, nc, trigram, source), freq in counter.most_common():
            w.writerow([pzy, czy, nzy, pc, cc, nc, trigram, freq, freq, source])


def main():
    parser = argparse.ArgumentParser(description="Build error n-gram boost CSVs from typing log.")
    parser.add_argument("--input", default="data/typing_log.csv", help="Input typing log CSV")
    parser.add_argument("--bigram-out", default="data/error_bigram_boost.csv", help="Output bigram CSV")
    parser.add_argument("--trigram-out", default="data/error_trigram_boost.csv", help="Output trigram CSV")
    parser.add_argument("--window", type=int, default=1, help="Context window radius around each mismatch (default: 1)")
    args = parser.parse_args()

    if args.window < 0:
        parser.error("--window must be >= 0")

    bi_counter = Counter()
    tri_counter = Counter()

    try:
        with open(args.input, "r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                process_row(row, bi_counter, tri_counter, args.window)
    except FileNotFoundError:
        print(f"Input not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    write_bigram_csv(args.bigram_out, bi_counter)
    write_trigram_csv(args.trigram_out, tri_counter)

    print(f"Wrote {len(bi_counter)} bigram rows to {args.bigram_out}")
    print(f"Wrote {len(tri_counter)} trigram rows to {args.trigram_out}")


if __name__ == "__main__":
    main()
