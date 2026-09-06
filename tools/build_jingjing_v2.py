#!/usr/bin/env python3
"""Build a jingjing term WBMM binary from a dictionary text file."""

import argparse
import os
import re
import sys
from collections import defaultdict
from typing import Optional

sys.path.insert(0, os.path.dirname(__file__))
import build_wbmm


# Opening bracket -> closing bracket.  We remove matched bracketed groups.
OPEN_TO_CLOSE = {
    "(": ")",
    "[": "]",
    "{": "}",
    "<": ">",
    "（": "）",
    "［": "］",
    "｛": "｝",
    "＜": "＞",
    "〔": "〕",
    "「": "」",
    "『": "』",
    "《": "》",
    "【": "】",
    "〖": "〗",
    "“": "”",
    "‘": "’",
    "«": "»",
    "‹": "›",
}
CLOSE_TO_OPEN = {v: k for k, v in OPEN_TO_CLOSE.items()}

# Punctuation stripped from the leading/trailing edges of a token.
LEAD_TRAIL_PUNCT = (
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "　。，、；：？！．…—・"
    "（）［］｛｝＜＞〔〕「」『』《》【】〖〗"
    "“”‘’«»‹›"
)
_LEAD_RE = re.compile(
    f"^[{re.escape(LEAD_TRAIL_PUNCT)}]+", re.UNICODE
)
_TRAIL_RE = re.compile(
    f"[{re.escape(LEAD_TRAIL_PUNCT)}]+$", re.UNICODE
)


def _remove_bracketed(text: str) -> str:
    """Remove all matched bracketed/parenthetical content from text."""
    stack = []  # (opening_char, start_index)
    spans = []  # (start, end_exclusive)

    for i, ch in enumerate(text):
        if ch in OPEN_TO_CLOSE:
            stack.append((ch, i))
        elif ch in CLOSE_TO_OPEN:
            if stack and stack[-1][0] == CLOSE_TO_OPEN[ch]:
                _, start = stack.pop()
                spans.append((start, i + 1))

    if not spans:
        return text

    # Difference array to mark excluded positions.
    diff = [0] * (len(text) + 1)
    for start, end in spans:
        diff[start] += 1
        if end < len(diff):
            diff[end] -= 1

    out = []
    depth = 0
    for i, ch in enumerate(text):
        depth += diff[i]
        if depth == 0:
            out.append(ch)
    return "".join(out)


def _strip_edges(text: str) -> str:
    """Strip leading/trailing punctuation and whitespace."""
    text = _LEAD_RE.sub("", text)
    text = _TRAIL_RE.sub("", text)
    return text.strip()


def _is_english_only(token: str) -> bool:
    """True if the token is only ASCII letters/digits (no CJK/other scripts)."""
    return bool(re.fullmatch(r"[A-Za-z0-9]+", token))

def _normalize(line: str, min_len: int) -> Optional[str]:
    """Return a cleaned, filtered term, or None if the line should be dropped."""
    raw = line.strip()
    if not raw:
        return None

    raw = _remove_bracketed(raw)
    tokens = [tok for tok in raw.split() if tok]
    if not tokens:
        return None

    kept = []
    for tok in tokens:
        tok = _strip_edges(tok)
        if not tok:
            continue
        if _is_english_only(tok):
            continue
        kept.append(tok)

    if not kept:
        return None

    # Tokens split only by whitespace; re-join into a single CJK/English term.
    term = "".join(kept)
    if len(term) < min_len:
        return None
    return term

def _build_mapping(terms, max_per_key):
    """Build all prefix->suffix expansions for each term, capping suffixes per prefix."""
    prefix_to_suffixes = defaultdict(list)
    for term in terms:
        for plen in range(1, len(term)):
            prefix = term[:plen]
            suffix = term[plen:]
            if suffix:
                prefix_to_suffixes[prefix].append(suffix)

    dropped_by_prefix = {}
    for prefix, suffixes in prefix_to_suffixes.items():
        if len(suffixes) > max_per_key:
            dropped = len(suffixes) - max_per_key
            dropped_by_prefix[prefix] = dropped
            prefix_to_suffixes[prefix] = suffixes[:max_per_key]

    return prefix_to_suffixes, dropped_by_prefix


def main():
    parser = argparse.ArgumentParser(description="Build a jingjing term WBMM binary.")
    parser.add_argument("--src", default="jingjing_ti_dictionary.txt", help="Input dictionary text file")
    parser.add_argument("--dst", default="YabomishIM/Resources/terms_jingjing.bin", help="Output WBMM binary path")
    parser.add_argument("--max-per-key", type=int, default=8, help="Maximum suffixes per prefix key")
    parser.add_argument("--min-len", type=int, default=2, help="Minimum term length to keep")
    args = parser.parse_args()

    if not os.path.isfile(args.src):
        print(f"Source file not found: {args.src}", file=sys.stderr)
        sys.exit(1)

    with open(args.src, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()

    total_lines = len(raw_lines)
    cleaned = []
    for line in raw_lines:
        term = _normalize(line, args.min_len)
        if term is not None:
            cleaned.append(term)

    # Preserve first occurrence while dropping duplicates.
    seen = set()
    unique_terms = []
    for t in cleaned:
        if t not in seen:
            seen.add(t)
            unique_terms.append(t)

    dropped_lines = total_lines - len(cleaned)
    normalized_terms = len(cleaned)
    unique_term_count = len(unique_terms)

    prefix_map, dropped_by_prefix = _build_mapping(unique_terms, args.max_per_key)

    print(f"Total lines:      {total_lines}")
    print(f"Dropped lines:    {dropped_lines}")
    print(f"Normalized terms: {normalized_terms}")
    print(f"Unique terms:     {unique_term_count}")
    if dropped_by_prefix:
        print("Prefixes at max-per-key limit:")
        for prefix in sorted(dropped_by_prefix, key=lambda p: -dropped_by_prefix[p]):
            print(f"  '{prefix}': {dropped_by_prefix[prefix]} suffix(es) dropped")
    else:
        print("No prefixes hit the max-per-key limit.")

    dst_dir = os.path.dirname(args.dst)
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)

    build_wbmm.build_wbmm(prefix_map, args.dst)
    print(f"Wrote {args.dst}")


if __name__ == "__main__":
    main()
