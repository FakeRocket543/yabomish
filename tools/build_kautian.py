#!/usr/bin/env python3
"""Build terms_kautian.bin (WBMM) from 教育部台灣閩南語常用詞辭典 kautian.ods.

Extracts 俗諺 (proverbs with 首字 category) as prefix→suffix entries.
For proverbs with comma: 前半句 prefix → 後半句 suffix.
For single phrases: character prefixes → remaining suffix.

Usage:
  python3 tools/build_kautian.py
"""
import sys, os
import pandas as pd
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'kautian.ods')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'terms_kautian.bin')

def main():
    df = pd.read_excel(SRC, engine='odf')

    # Extract proverbs (首字 category)
    proverbs = df[df['分類'].str.contains('首字', na=False)]['漢字'].dropna().tolist()
    # Clean: remove trailing period, strip
    proverbs = [p.rstrip('。').strip() for p in proverbs if len(p) >= 4]
    proverbs = sorted(set(proverbs))

    entries = defaultdict(list)
    MAX_PER_KEY = 8

    for p in proverbs:
        # If has comma, split into front→back
        if '，' in p:
            parts = p.split('，', 1)
            front = parts[0].strip()
            back = parts[1].strip()
            if front and back:
                # front as key, back as value
                for plen in range(2, len(front) + 1):
                    prefix = front[:plen]
                    suffix = front[plen:] + '，' + back if plen < len(front) else back
                    if suffix and len(entries[prefix]) < MAX_PER_KEY:
                        entries[prefix].append(suffix)
        else:
            # Single phrase: prefix expansion
            for plen in range(2, len(p)):
                prefix = p[:plen]
                suffix = p[plen:]
                if suffix and len(entries[prefix]) < MAX_PER_KEY:
                    entries[prefix].append(suffix)

    print(f"Kautian: {len(proverbs)} proverbs → {len(entries)} prefix keys")
    build_wbmm(dict(entries), DST)

if __name__ == '__main__':
    main()
