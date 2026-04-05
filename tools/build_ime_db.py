#!/usr/bin/env python3
"""
組合所有資料層 → 單一 yabomish_ime.db

Tables:
  zhuyin_base    (zhuyin, char, freq)           — 注音→字 + 字頻
  bigram         (prev_zy, cur_zy, char, freq)  — bigram boost
  ner_phrase     (phrase, type, freq, zhuyin_key, community) — NER 詞組 + 注音鍵
  community      (entity, type, freq, community) — 社群 lookup
"""
import json, sqlite3, time
from pathlib import Path
import pandas as pd

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"
DATA = BASE / "data"
DB_PATH = DATA / "yabomish_ime.db"


def build():
    t0 = time.time()

    # Load zhuyin mappings
    with open(RES / "zhuyin_data.json") as f:
        zd = json.load(f)
    z2c = zd["zhuyin_to_chars"]
    c2z = zd["char_to_zhuyins"]

    with open(RES / "char_freq.json") as f:
        char_freq = json.load(f)

    with open(RES / "bigram_boost.json") as f:
        bigram_boost = json.load(f)

    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")

    # ── Table 1: zhuyin_base ──
    print("[1/4] zhuyin_base...")
    conn.execute("DROP TABLE IF EXISTS zhuyin_base")
    conn.execute("CREATE TABLE zhuyin_base (zhuyin TEXT, char TEXT, freq INTEGER)")
    rows = []
    for zy, chars in z2c.items():
        for i, ch in enumerate(chars):
            freq = char_freq.get(ch, 0)
            rows.append((zy, ch, freq))
    conn.executemany("INSERT INTO zhuyin_base VALUES (?,?,?)", rows)
    conn.execute("CREATE INDEX idx_zb_zhuyin ON zhuyin_base(zhuyin)")
    print(f"  {len(rows):,} rows")

    # ── Table 2: bigram ──
    print("[2/4] bigram...")
    conn.execute("DROP TABLE IF EXISTS bigram")
    conn.execute("CREATE TABLE bigram (prev_zy TEXT, cur_zy TEXT, char TEXT, freq INTEGER)")
    rows = []
    for prev_zy, inner in bigram_boost.items():
        for cur_zy, pairs in inner.items():
            for pair in pairs:
                rows.append((prev_zy, cur_zy, pair[0], pair[1]))
    conn.executemany("INSERT INTO bigram VALUES (?,?,?,?)", rows)
    conn.execute("CREATE INDEX idx_bg ON bigram(prev_zy, cur_zy)")
    print(f"  {len(rows):,} rows")

    # ── Table 3: ner_phrase (NER 實體 + 注音鍵) ──
    print("[3/4] ner_phrase...")
    conn.execute("DROP TABLE IF EXISTS ner_phrase")
    conn.execute("""CREATE TABLE ner_phrase (
        phrase TEXT, type TEXT, freq INTEGER,
        zhuyin_key TEXT, community INTEGER)""")

    # Load community data
    comm_df = pd.read_csv(DATA / "wiki_kg_community.csv")
    entity2comm = dict(zip(comm_df["entity"], comm_df["community"]))

    # Load NER entities, filter to freq >= 5 and meaningful types
    ner_df = pd.read_parquet(DATA / "wiki_ner_entities.parquet")
    skip_types = {"", "CARDINAL", "ORDINAL", "PERCENT", "MONEY", "QUANTITY"}
    ner_df = ner_df[~ner_df["type"].isin(skip_types)]
    ner_df = ner_df[ner_df["freq"] >= 5]
    ner_df = ner_df[ner_df["entity"].str.len() >= 2]  # multi-char only
    # Remove wiki markup noise
    ner_df = ner_df[~ner_df["entity"].str.match(r"^(Category|category|thumb|File|Image|Catego)")]
    print(f"  NER 候選: {len(ner_df):,}")

    # Generate zhuyin keys for each phrase
    def phrase_to_zhuyin(phrase):
        """Convert phrase to zhuyin key using first reading of each char."""
        parts = []
        for ch in phrase:
            zhuyins = c2z.get(ch)
            if not zhuyins:
                return None  # can't convert
            parts.append(zhuyins[0])  # use first (most common) reading
        return "".join(parts)

    rows = []
    no_zy = 0
    for _, r in ner_df.iterrows():
        zy = phrase_to_zhuyin(r["entity"])
        if zy is None:
            no_zy += 1
            continue
        comm = entity2comm.get(r["entity"], -1)
        rows.append((r["entity"], r["type"], int(r["freq"]), zy, int(comm)))

    conn.executemany("INSERT INTO ner_phrase VALUES (?,?,?,?,?)", rows)
    conn.execute("CREATE INDEX idx_np_zy ON ner_phrase(zhuyin_key)")
    conn.execute("CREATE INDEX idx_np_phrase ON ner_phrase(phrase)")
    print(f"  {len(rows):,} phrases (skipped {no_zy:,} without zhuyin)")

    # ── Table 4: community ──
    print("[4/4] community...")
    conn.execute("DROP TABLE IF EXISTS community")
    conn.execute("CREATE TABLE community (entity TEXT, type TEXT, freq INTEGER, community INTEGER)")
    comm_rows = [(r["entity"], r["type"], int(r["freq"]), int(r["community"]))
                 for _, r in comm_df.iterrows()]
    conn.executemany("INSERT INTO community VALUES (?,?,?,?)", comm_rows)
    conn.execute("CREATE INDEX idx_comm_entity ON community(entity)")
    conn.execute("CREATE INDEX idx_comm_id ON community(community)")
    print(f"  {len(comm_rows):,} rows")

    conn.commit()

    # Stats
    print(f"\n=== {DB_PATH} ===")
    for tbl in ["zhuyin_base", "bigram", "ner_phrase", "community"]:
        n = conn.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0]
        print(f"  {tbl:15s}: {n:,}")

    conn.close()
    import os
    print(f"\n  Size: {os.path.getsize(DB_PATH)/1e6:.1f} MB")
    print(f"  Time: {time.time()-t0:.1f}s")


if __name__ == "__main__":
    build()
