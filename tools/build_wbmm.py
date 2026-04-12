#!/usr/bin/env python3
"""Build WBMM binary from TSV (word\tfreq) or prefix-expansion dict.

Usage:
  # News word freq → bigram-style WBMM (key=word, values=top next words by freq)
  python3 build_wbmm.py news /path/to/news_word_freq.tsv /path/to/word_news.bin
  
  # Yoji / chengyu → prefix WBMM (key=prefix, values=full terms)
  python3 build_wbmm.py prefix /path/to/terms.txt /path/to/output.bin [--min-len 4]
"""
import struct, sys, os, re

def _is_clean_key(s: str) -> bool:
    if len(s) < 2: return False
    if '\t' in s: return False
    if re.search(r'[a-zA-Z]', s): return False
    if re.search(r'^[\d.]', s): return False
    if '--' in s or "'''" in s: return False
    return True

def build_wbmm(entries: dict[str, list[str]], out_path: str):
    """entries: {key_str: [val_str, ...]} sorted by key."""
    # Collect all unique strings
    strings = {}  # str -> (offset, length)
    blob = bytearray()
    def intern(s: str) -> tuple[int, int]:
        if s in strings: return strings[s]
        b = s.encode('utf-8')
        off = len(blob)
        blob.extend(b)
        strings[s] = (off, len(b))
        return (off, len(b))
    
    # Intern all strings
    sorted_keys = sorted(entries.keys(), key=lambda s: s.encode('utf-8'))
    key_entries = []  # [(str_off, str_len, val_start, val_count)]
    val_entries = []  # [(str_off, str_len)]
    
    for k in sorted_keys:
        ko, kl = intern(k)
        vs = entries[k]
        val_start = len(val_entries)
        for v in vs[:65535]:
            vo, vl = intern(v)
            val_entries.append((vo, vl))
        key_entries.append((ko, kl, val_start, len(vs[:65535])))
    
    # Layout: header(16) + blob + key_index + val_index
    header_size = 16
    blob_off = header_size  # strings start right after header
    key_index_off = blob_off + len(blob)
    val_index_off = key_index_off + len(key_entries) * 12
    
    # Adjust string offsets (add blob_off)
    out = bytearray()
    # Header
    out.extend(b'WBMM')
    out.extend(struct.pack('<I', len(key_entries)))
    out.extend(struct.pack('<I', key_index_off))
    out.extend(struct.pack('<I', val_index_off))
    # Blob
    out.extend(blob)
    # Key index
    for so, sl, vs, vc in key_entries:
        out.extend(struct.pack('<I', blob_off + so))
        out.extend(struct.pack('<H', sl))
        out.extend(struct.pack('<I', vs))
        out.extend(struct.pack('<H', vc))
    # Val index
    for vo, vl in val_entries:
        out.extend(struct.pack('<I', blob_off + vo))
        out.extend(struct.pack('<H', vl))
    
    with open(out_path, 'wb') as f:
        f.write(out)
    print(f"WBMM: {len(key_entries)} keys, {len(val_entries)} vals, {len(out)} bytes → {out_path}")

def build_news(tsv_path: str, out_path: str):
    """Build prefix-expansion WBMM from news word freq TSV (word\\tfreq).
    Key = each prefix (2~N-1 chars), Value = full words sorted by freq."""
    from collections import defaultdict
    words = []
    with open(tsv_path, encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2 and len(parts[0]) >= 2:
                try:
                    words.append((parts[0], int(parts[1])))
                except ValueError:
                    continue
    words.sort(key=lambda x: -x[1])
    words = [(w, f) for w, f in words if _is_clean_key(w)]
    # Build prefix → [full words] (top N per prefix)
    entries = defaultdict(list)
    MAX_PER_KEY = 5
    for word, freq in words:
        for plen in range(1, len(word)):
            prefix = word[:plen]
            if len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(word)
    print(f"News: {len(words)} words → {len(entries)} prefix keys")
    build_wbmm(dict(entries), out_path)

def build_prefix(txt_path: str, out_path: str, min_len: int = 4):
    """Build prefix-expansion WBMM from a text file (one term per line)."""
    from collections import defaultdict
    terms = []
    with open(txt_path, encoding='utf-8') as f:
        for line in f:
            t = line.strip()
            if len(t) >= min_len:
                terms.append(t)
    terms = sorted(set(terms))
    entries = defaultdict(list)
    MAX_PER_KEY = 5
    for term in terms:
        for plen in range(1, len(term)):
            prefix = term[:plen]
            if len(entries[prefix]) < MAX_PER_KEY:
                entries[prefix].append(term)
    print(f"Prefix: {len(terms)} terms → {len(entries)} prefix keys")
    build_wbmm(dict(entries), out_path)

def build_bigram_json(json_path: str, out_path: str):
    """Build WBMM from word_bigram.json {key: [val1, val2, ...]}. Filters junk keys."""
    import json
    with open(json_path) as f:
        data = json.load(f)
    entries = {}
    for k, vals in data.items():
        if not _is_clean_key(k): continue
        clean = [v for v in vals if len(v) >= 1]
        if clean:
            entries[k] = clean
    print(f"Bigram JSON: {len(data)} → {len(entries)} clean keys")
    build_wbmm(entries, out_path)

if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'news':
        build_news(sys.argv[2], sys.argv[3])
    elif mode == 'prefix':
        min_len = 4
        if '--min-len' in sys.argv:
            min_len = int(sys.argv[sys.argv.index('--min-len') + 1])
        build_prefix(sys.argv[2], sys.argv[3], min_len)
    elif mode == 'bigram_json':
        build_bigram_json(sys.argv[2], sys.argv[3])
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
        sys.exit(1)
