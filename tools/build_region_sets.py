#!/usr/bin/env python3
"""Build region_tw.txt and region_cn.txt from NAER cross-strait term CSVs."""
import csv, glob, re, os

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'naer_terms', 'csv')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources')

def clean(s):
    s = re.sub(r'[\[{〈（\(].*?[\]}\u3009）\)]', '', s)
    s = s.split(';')[0].split('；')[0].split('：')[0]
    return s.strip()

def main():
    tw, cn = set(), set()
    for f in sorted(glob.glob(os.path.join(SRC, '*兩岸*壓縮檔*.csv')) + glob.glob(os.path.join(SRC, '兩岸*壓縮檔*.csv'))):
        with open(f, encoding='utf-8') as fh:
            for row in csv.DictReader(fh):
                t = clean(row.get('中文名稱', ''))
                c = clean(row.get('中國大陸譯名', ''))
                if t and c and t != c and len(t) >= 2 and len(c) >= 2:
                    tw.add(t)
                    cn.add(c)

    for name, terms in [('region_tw.txt', tw), ('region_cn.txt', cn)]:
        path = os.path.join(DST, name)
        with open(path, 'w', encoding='utf-8') as f:
            for t in sorted(terms):
                f.write(t + '\n')
        print(f'{name}: {len(terms):,} terms → {path}')

if __name__ == '__main__':
    main()
