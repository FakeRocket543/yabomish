#!/usr/bin/env python3
"""Build terms_hakka.bin (WBMM) from 教育部臺灣客語辭典 6 dialect ODS files.

Merges all 6 dialects, deduplicates by 漢字 詞目, builds prefix→suffix WBMM.

Usage:
  python3 tools/build_hakka.py
"""
import sys, os, glob
import pandas as pd
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'hakka')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'terms_hakka.bin')

def main():
    all_terms = set()
    for f in sorted(glob.glob(os.path.join(SRC, '*.ods'))):
        df = pd.read_excel(f, engine='odf')
        for t in df['詞目'].dropna():
            t = str(t).strip()
            if len(t) >= 2:
                all_terms.add(t)

    terms = sorted(all_terms)
    entries = defaultdict(list)
    MAX_PER_KEY = 8
    for term in terms:
        for plen in range(2, len(term)):
            prefix = term[:plen]
            suffix = term[plen:]
            if suffix and len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(suffix)

    print(f"Hakka: {len(terms):,} terms (6 dialects) → {len(entries):,} prefix keys")
    build_wbmm(dict(entries), DST)

if __name__ == '__main__':
    main()
