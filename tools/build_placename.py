#!/usr/bin/env python3
"""Build terms_placename.bin from MOE place name data (railways + MRT stations).
Build terms_ttg.bin from MOE academic terms with Taiwanese translations.

Sources:
- 教育部以本土語言標注臺灣地名 (CC-BY 3.0 TW)
- 教育部臺灣台語學科術語 (CC-BY 3.0 TW)
"""
import sys, os, glob
import pandas as pd
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm

BASE = os.path.join(os.path.dirname(__file__), '..', 'data', 'placename')
RES = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources')

def build_terms(terms, out_path, label):
    terms = sorted(set(t for t in terms if len(t) >= 2))
    entries = defaultdict(list)
    for term in terms:
        for plen in range(2, len(term)):
            prefix = term[:plen]
            if len(entries[prefix]) < 8:
                entries[prefix].append(term[plen:])
    print(f"{label}: {len(terms):,} terms → {len(entries):,} prefix keys")
    build_wbmm(dict(entries), out_path)

def main():
    # 1. Place names from ODT files
    places = set()
    for f in sorted(glob.glob(os.path.join(BASE, 'extracted', '*.odt'))):
        df = pd.read_excel(f, engine='odf')
        if '國語' in df.columns:
            for n in df['國語'].dropna():
                n = str(n).strip()
                if len(n) >= 2:
                    places.add(n)
    build_terms(places, os.path.join(RES, 'terms_placename.bin'), 'Placename')

    # 2. Academic terms (TTG)
    ttg_path = os.path.join(BASE, 'ttg.ods')
    df = pd.read_excel(ttg_path, engine='odf')
    terms = set()
    for t in df['學科術語'].dropna():
        t = str(t).strip()
        if len(t) >= 2:
            terms.add(t)
    build_terms(terms, os.path.join(RES, 'terms_ttg.bin'), 'TTG')

if __name__ == '__main__':
    main()
