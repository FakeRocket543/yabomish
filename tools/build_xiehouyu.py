#!/usr/bin/env python3
"""Build terms_xiehouyu.bin (WBMM) from chinese-xinhua xiehouyu dataset.

Structure: riddle prefix → answer suffix.
Source: https://github.com/pwxcoo/chinese-xinhua (14K entries, s2t converted)
"""
import sys, os, json
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'xiehouyu_trad.json')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'terms_xiehouyu.bin')

def main():
    with open(SRC, encoding='utf-8') as f:
        data = json.load(f)

    entries = defaultdict(list)
    MAX_PER_KEY = 8
    for item in data:
        riddle = item['riddle'].strip()
        answer = item['answer'].strip()
        if not riddle or not answer:
            continue
        # riddle prefix → "riddle_suffix——answer"
        for plen in range(1, len(riddle) + 1):
            prefix = riddle[:plen]
            suffix = riddle[plen:] + '——' + answer if plen < len(riddle) else answer
            if suffix and len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(suffix)

    print(f"Xiehouyu: {len(data):,} sayings → {len(entries):,} prefix keys")
    build_wbmm(dict(entries), DST)

if __name__ == '__main__':
    main()
