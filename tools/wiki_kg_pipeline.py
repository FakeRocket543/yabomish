#!/usr/bin/env python3
"""
維基 NER 實體 × 條目標題 → 知識圖譜

步驟：
1. 從 wiki XML dump 抽取所有條目標題
2. 篩選 NER 實體：匹配條目標題 + freq >= 3 + 有意義類型
3. 掃描 NER 批次檔，建立段落級共現邊
4. 輸出 nodes.csv / edges.csv / kg.graphml
"""
import bz2, json, re, time
from collections import Counter
from itertools import combinations
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent.parent
WORK = BASE / "data" / "wiki_work"
OUT = BASE / "data"
DUMP = WORK / "zhwiki-latest-pages-articles.xml.bz2"
NER_DIR = WORK / "ner_batches"
ENTITY_PQ = OUT / "wiki_ner_entities.parquet"

SKIP_TYPES = {"", "CARDINAL", "ORDINAL", "PERCENT", "MONEY", "QUANTITY"}
MIN_FREQ = 3
MIN_EDGE_WEIGHT = 2


def step1_extract_titles():
    """從 wiki XML dump 抽取條目標題（跳過特殊頁面）"""
    print("[1/4] 抽取維基條目標題...")
    ns = "{http://www.mediawiki.org/xml/export-0.11/}"
    from xml.etree.ElementTree import iterparse

    skip_prefixes = (
        "Wikipedia:", "Template:", "Category:", "File:", "Help:",
        "Portal:", "Draft:", "Module:", "MediaWiki:", "User:",
        "維基百科:", "模板:", "分類:", "檔案:", "幫助:",
        "主題:", "草稿:", "模組:", "使用者:",
    )
    titles = set()
    t0 = time.time()
    last_report = 0
    with bz2.open(str(DUMP), "rt", encoding="utf-8") as f:
        for event, elem in iterparse(f, events=("end",)):
            if elem.tag == f"{ns}title":
                t = elem.text
                if t and not t.startswith(skip_prefixes):
                    titles.add(t)
                    n = len(titles)
                    if n >= last_report + 200000:
                        last_report = n
                        print(f"  {n:,} titles... ({time.time()-t0:.0f}s)")
            elem.clear()

    print(f"  共 {len(titles):,} 條目標題 ({time.time()-t0:.0f}s)")
    # 存檔供後續使用
    title_file = WORK / "wiki_titles.txt"
    with open(title_file, "w", encoding="utf-8") as f:
        for t in sorted(titles):
            f.write(t + "\n")
    print(f"  → {title_file}")
    return titles


def step2_filter_nodes(titles):
    """篩選 NER 實體：匹配條目標題 + 有意義類型 + freq >= MIN_FREQ"""
    print(f"\n[2/4] 篩選節點（匹配條目標題, freq>={MIN_FREQ}）...")
    df = pd.read_parquet(ENTITY_PQ)
    before = len(df)
    df = df[~df["type"].isin(SKIP_TYPES)]
    df = df[df["freq"] >= MIN_FREQ]
    df = df[df["entity"].isin(titles)]
    print(f"  {before:,} → {len(df):,} 實體（匹配條目標題）")
    print(f"  類型分佈:")
    for t, g in df.groupby("type"):
        print(f"    {t:15s}: {len(g):,} 種, 總頻次 {g['freq'].sum():,}")
    return set(df["entity"].values), df


def step3_build_edges(node_set):
    """掃描 NER 批次檔，建立段落級共現邊"""
    print(f"\n[3/4] 建立共現邊（{len(node_set):,} 節點）...")
    edges = Counter()
    batch_files = sorted(NER_DIR.glob("ner_batch_*.jsonl"))
    total_segs = 0
    t0 = time.time()

    for bf in batch_files:
        with open(bf, encoding="utf-8") as f:
            for line in f:
                total_segs += 1
                ents = json.loads(line)
                # 取出在 node_set 中的不重複實體
                matched = set()
                for e, tp in ents:
                    if e in node_set and tp not in SKIP_TYPES:
                        matched.add(e)
                if len(matched) >= 2:
                    for a, b in combinations(sorted(matched), 2):
                        edges[(a, b)] += 1
        elapsed = time.time() - t0
        print(f"  {bf.name}: 累計 {total_segs:,} 段, "
              f"{len(edges):,} 邊 ({elapsed:.0f}s)")

    # 過濾低權重邊
    edges = {k: v for k, v in edges.items() if v >= MIN_EDGE_WEIGHT}
    print(f"  共現邊（weight>={MIN_EDGE_WEIGHT}）: {len(edges):,}")
    return edges


def step4_output(node_df, edges):
    """輸出 nodes.csv / edges.csv / kg.graphml"""
    print(f"\n[4/4] 輸出知識圖譜...")

    # 只保留有邊的節點
    edge_nodes = set()
    for (a, b) in edges:
        edge_nodes.add(a)
        edge_nodes.add(b)
    node_df = node_df[node_df["entity"].isin(edge_nodes)]

    # nodes
    nodes_file = OUT / "wiki_kg_nodes.csv"
    node_df.to_csv(nodes_file, index=False)
    print(f"  節點: {len(node_df):,} → {nodes_file}")

    # edges
    edge_rows = [{"source": a, "target": b, "weight": w}
                 for (a, b), w in edges.items()]
    edge_df = pd.DataFrame(edge_rows)
    edge_df = edge_df.sort_values("weight", ascending=False).reset_index(drop=True)
    edges_file = OUT / "wiki_kg_edges.csv"
    edge_df.to_csv(edges_file, index=False)
    print(f"  邊:   {len(edge_df):,} → {edges_file}")

    # graphml
    try:
        import networkx as nx
        G = nx.Graph()
        for _, row in node_df.iterrows():
            G.add_node(row["entity"], type=row["type"], freq=int(row["freq"]))
        for (a, b), w in edges.items():
            G.add_edge(a, b, weight=w)
        gml_file = OUT / "wiki_kg.graphml"
        nx.write_graphml(G, str(gml_file))
        print(f"  GraphML: {gml_file}")
    except ImportError:
        print("  ⚠️  networkx 未安裝，跳過 graphml 輸出")

    # summary
    print(f"\n=== 知識圖譜摘要 ===")
    print(f"  節點: {len(node_df):,}")
    print(f"  邊:   {len(edge_df):,}")
    print(f"  Top 20 邊:")
    print(edge_df.head(20).to_string(index=False))


if __name__ == "__main__":
    t_start = time.time()

    title_file = WORK / "wiki_titles.txt"
    if title_file.exists():
        print("[1/4] 載入已有標題...")
        titles = set(open(title_file, encoding="utf-8").read().splitlines())
        print(f"  {len(titles):,} 條目標題")
    else:
        titles = step1_extract_titles()

    node_set, node_df = step2_filter_nodes(titles)
    edges = step3_build_edges(node_set)
    step4_output(node_df, edges)

    print(f"\n✅ 完成！總耗時 {(time.time()-t_start)/60:.1f} 分鐘")
