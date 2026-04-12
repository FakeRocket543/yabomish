#!/usr/bin/env python3
"""Build terms_jingjing.bin (WBMM) from jingjing_ti_dictionary.txt.

Output format matches chengyu.bin: key=prefix, value=remaining suffix.
This way SuggestionEngine's dropFirst(prefix.count) works correctly.

Usage:
  python3 tools/build_jingjing.py
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm
from collections import defaultdict

SRC = os.path.join(os.path.dirname(__file__), '..', 'jingjing_ti_dictionary.txt')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'terms_jingjing.bin')

def main():
    terms = []
    with open(SRC, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('=') or line.startswith('【'):
                continue
            # Skip header lines
            if line.startswith('晶晶體') or line.startswith('來源') or line.startswith('整理日期') or line.startswith('規則'):
                continue
            # Strip parenthetical notes like （check）
            if '（' in line:
                line = line[:line.index('（')].strip()
            if len(line) >= 2:
                terms.append(line)

    terms = sorted(set(terms))

    # Build suffix-style entries (same as chengyu.bin):
    # key = prefix (1~N-1 chars), value = remaining suffix
    entries = defaultdict(list)
    MAX_PER_KEY = 8
    for term in terms:
        for plen in range(1, len(term)):
            prefix = term[:plen]
            suffix = term[plen:]
            if suffix and len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(suffix)

    print(f"Jingjing: {len(terms)} terms → {len(entries)} prefix keys")
    build_wbmm(dict(entries), DST)

if __name__ == '__main__':
    main()
