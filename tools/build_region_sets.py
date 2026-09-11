#!/usr/bin/env python3
"""Build region_tw.txt and region_cn.txt from NAER cross-strait term CSVs."""
import csv, glob, re, os, sys

SRC = os.path.join(os.path.dirname(__file__), '..', 'data', 'naer_terms', 'csv')
DST = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources')

def clean(s):
    s = re.sub(r'[\[{〈（\(].*?[\]}\u3009）\)]', '', s)
    s = s.split(';')[0].split('；')[0].split('：')[0]
    return s.strip()


def _atomic_write(path, text):
    """寫到 .tmp 再原子置換，避免中斷留下半個出貨檔。"""
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, path)

def main():
    files = sorted(glob.glob(os.path.join(SRC, '*兩岸*壓縮檔*.csv')) + glob.glob(os.path.join(SRC, '兩岸*壓縮檔*.csv')))
    if not files:
        sys.exit(f'❌ 找不到 NAER CSV（{SRC}/*兩岸*壓縮檔*.csv）——不覆寫 region_*.txt')

    tw, cn = set(), set()
    for f in files:
        with open(f, encoding='utf-8') as fh:
            for row in csv.DictReader(fh):
                t = clean(row.get('中文名稱', ''))
                c = clean(row.get('中國大陸譯名', ''))
                if t and c and t != c and len(t) >= 2 and len(c) >= 2:
                    tw.add(t)
                    cn.add(c)

    if not tw or not cn:
        sys.exit(f'❌ NAER CSV 解析出 0 詞（tw={len(tw)}, cn={len(cn)}）——不覆寫 region_*.txt')

    for name, terms in [('region_tw.txt', tw), ('region_cn.txt', cn)]:
        path = os.path.join(DST, name)
        _atomic_write(path, ''.join(t + '\n' for t in sorted(terms)))
        print(f'{name}: {len(terms):,} terms → {path}')

if __name__ == '__main__':
    main()
