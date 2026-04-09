#!/usr/bin/env python3
"""從 zhwiki XML dump 抽取條目→分類映射"""
import bz2, re, time, json
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DUMP = BASE / "data" / "wiki_work" / "zhwiki-latest-pages-articles.xml.bz2"
OUT = BASE / "data" / "wiki_work" / "wiki_categories.jsonl"

# Category regex: [[Category:XXX]] or [[分類:XXX]]
CAT_RE = re.compile(r'\[\[(?:Category|分類):([^\]|]+)', re.IGNORECASE)

skip_ns = (
    "Wikipedia:", "Template:", "Category:", "File:", "Help:",
    "Portal:", "Draft:", "Module:", "MediaWiki:", "User:",
    "維基百科:", "模板:", "分類:", "檔案:", "幫助:",
    "主題:", "草稿:", "模組:", "使用者:",
)

ns = "{http://www.mediawiki.org/xml/export-0.11/}"
t0 = time.time()
count = 0
cat_count = 0

from xml.etree.ElementTree import iterparse

with bz2.open(str(DUMP), "rt", encoding="utf-8") as f_in, \
     open(OUT, "w", encoding="utf-8") as f_out:
    title = None
    for event, elem in iterparse(f_in, events=("end",)):
        if elem.tag == f"{ns}title":
            title = elem.text
        elif elem.tag == f"{ns}text" and title:
            if not title.startswith(skip_ns) and elem.text:
                cats = CAT_RE.findall(elem.text)
                if cats:
                    cats = [c.strip() for c in cats]
                    f_out.write(json.dumps({"title": title, "cats": cats}, ensure_ascii=False) + "\n")
                    cat_count += len(cats)
                    count += 1
                    if count % 50000 == 0:
                        print(f"  {count:,} articles, {cat_count:,} cat links ({time.time()-t0:.0f}s)")
            title = None
            elem.clear()
        elif elem.tag == f"{ns}page":
            elem.clear()

print(f"\n✅ {count:,} articles with categories, {cat_count:,} total cat links")
print(f"   → {OUT}")
print(f"   耗時 {(time.time()-t0)/60:.1f} 分鐘")
