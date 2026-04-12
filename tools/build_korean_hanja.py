#!/usr/bin/env python3
"""Build terms_korean.bin (WBMM) from Kengdic Korean-English dictionary.

Extracts hanja (漢字) terms, filters verb forms, builds prefix→suffix WBMM.
License: MPL 2.0 / LGPL 2.0+ (Kengdic)
Source: https://github.com/garfieldnate/kengdic
"""
import sys, os, csv, re
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from build_wbmm import build_wbmm, _is_clean_key

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'kengdic.tsv')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'terms_korean.bin')

def main():
    terms = set()
    with open(SRC, encoding='utf-8') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            h = (row.get('hanja') or '').strip()
            if len(h) < 2: continue
            if re.search(r'[a-zA-Z]', h): continue
            if any(v in h for v in ('하다', '되다', '시키다', '짓다')): continue
            terms.add(h)

    terms = sorted(terms)
    entries = defaultdict(list)
    MAX_PER_KEY = 8
    for term in terms:
        for plen in range(1, len(term)):
            prefix = term[:plen]
            suffix = term[plen:]
            if suffix and len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(suffix)

    print(f"Korean hanja: {len(terms):,} terms → {len(entries):,} prefix keys")
    build_wbmm(dict(entries), DST)

if __name__ == '__main__':
    main()
