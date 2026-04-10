#!/usr/bin/env python3
"""Convert bigram_boost.json to binary mmap format.

Input JSON: { prevZhuyin: { curZhuyin: [[char, freq], ...] } }
Output binary:
  Header: "BGBT" (4B) + entryCount (4B LE)
  Index:  entryCount × (prevZy_off:4, prevZy_len:2, curZy_off:4, curZy_len:2, pairs_off:4, pairs_count:2) = 20B each
  Strings: UTF-8 encoded zhuyin keys
  Pairs:   char_off:4, char_len:2, freq:2 = 8B each
  CharPool: UTF-8 encoded chars
"""
import json, struct, sys

def build(src, dst):
    with open(src) as f:
        data = json.load(f)

    entries = []  # (prevZy, curZy, [(char, freq)])
    for pzy, inner in data.items():
        for czy, pairs in inner.items():
            clean = [(p[0], int(p[1])) for p in pairs if len(p) >= 2]
            if clean:
                entries.append((pzy, czy, clean))

    print(f"{len(entries)} entries from {src}")

    # Build pools
    str_pool = bytearray()
    str_map = {}
    def add_str(s):
        if s in str_map: return str_map[s]
        off = len(str_pool)
        b = s.encode('utf-8')
        str_pool.extend(b)
        str_map[s] = (off, len(b))
        return (off, len(b))

    # Pre-add all strings
    for pzy, czy, pairs in entries:
        add_str(pzy)
        add_str(czy)
        for ch, _ in pairs:
            add_str(ch)

    # Build index + pairs
    HEADER = 8
    INDEX_ENTRY = 20
    index_size = len(entries) * INDEX_ENTRY

    # Pairs section
    pair_records = []  # list of (char_str_off, char_str_len, freq)
    pair_offsets = []  # (start_idx, count) per entry
    for pzy, czy, pairs in entries:
        start = len(pair_records)
        for ch, freq in pairs:
            co, cl = str_map[ch]
            pair_records.append((co, cl, min(freq, 65535)))
        pair_offsets.append((start, len(pairs)))

    pairs_section_off = HEADER + index_size
    str_section_off = pairs_section_off + len(pair_records) * 8

    # Write
    out = bytearray()
    # Header
    out.extend(b'BGBT')
    out.extend(struct.pack('<I', len(entries)))
    # Index
    for i, (pzy, czy, _) in enumerate(entries):
        po, pl = str_map[pzy]
        co, cl = str_map[czy]
        ps, pc = pair_offsets[i]
        out.extend(struct.pack('<IHIHIH',
            str_section_off + po, pl,
            str_section_off + co, cl,
            pairs_section_off + ps * 8, pc))
    # Pairs
    for co, cl, freq in pair_records:
        out.extend(struct.pack('<IHH', str_section_off + co, cl, freq))
    # String pool
    out.extend(str_pool)

    with open(dst, 'wb') as f:
        f.write(out)
    print(f"BGBT: {len(entries)} entries, {len(pair_records)} pairs, {len(out)} bytes → {dst}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.json output.bin")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
