#!/usr/bin/env python3
"""Rebuild terms_*.bin: pure NAER + filtered wiki entities (freq>=10, clean keys only).

1. Restore pure NAER bins from git (commit 0ff0673)
2. Load wiki domain entities, filter by NER freq>=10 and clean key rules
3. Merge and rebuild WBMM bins
"""
import json, re, subprocess, os, sys
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, str(Path(__file__).parent))
from build_wbmm import build_wbmm, _is_clean_key

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"
WIKI_ENTITIES = BASE / "data" / "wiki_work" / "wiki_domain_entities_trad.json"
NER_PARQUET = BASE / "data" / "wiki_ner_entities.parquet"
NAER_COMMIT = "0ff0673"  # pure NAER, before wiki merge
FREQ_THRESHOLD = 50

DOMAIN_FILES = {
    "it": "terms_it", "ee": "terms_ee", "med": "terms_med", "law": "terms_law",
    "phy": "terms_phy", "chem": "terms_chem", "bio": "terms_bio", "math": "terms_math",
    "biz": "terms_biz", "edu": "terms_edu", "geo": "terms_geo", "eng": "terms_eng",
    "art": "terms_art", "mil": "terms_mil", "marine": "terms_marine",
    "material": "terms_material", "agri": "terms_agri", "media": "terms_media",
    "social": "terms_social", "govt": "terms_govt",
}

def restore_naer_bins():
    """Restore pure NAER bins from git."""
    for domain, fname in DOMAIN_FILES.items():
        binfile = f"YabomishIM/Resources/{fname}.bin"
        r = subprocess.run(["git", "show", f"{NAER_COMMIT}:{binfile}"],
                           capture_output=True, cwd=str(BASE))
        if r.returncode == 0:
            (RES / f"{fname}.bin").write_bytes(r.stdout)
            print(f"  restored {fname}.bin ({len(r.stdout):,} bytes)")
        else:
            print(f"  SKIP {fname}.bin (not in {NAER_COMMIT})")

def load_ner_freq():
    """Load NER entity frequencies from parquet."""
    import pandas as pd
    df = pd.read_parquet(NER_PARQUET)
    return dict(zip(df["entity"], df["freq"]))

def load_naer_terms(binpath):
    """Read existing WBMM bin and extract {key: [vals]}."""
    import struct
    if not binpath.exists():
        return {}
    d = binpath.read_bytes()
    if len(d) < 16 or d[:4] != b'WBMM':
        return {}
    kc = struct.unpack_from('<I', d, 4)[0]
    ki = struct.unpack_from('<I', d, 8)[0]
    vi = struct.unpack_from('<I', d, 12)[0]
    entries = {}
    for i in range(kc):
        eo = ki + i * 12
        so = struct.unpack_from('<I', d, eo)[0]
        sl = struct.unpack_from('<H', d, eo + 4)[0]
        vs = struct.unpack_from('<I', d, eo + 6)[0]
        vc = struct.unpack_from('<H', d, eo + 10)[0]
        key = d[so:so+sl].decode('utf-8', errors='replace')
        vals = []
        for j in range(vc):
            vo = vi + (vs + j) * 6
            vso = struct.unpack_from('<I', d, vo)[0]
            vsl = struct.unpack_from('<H', d, vo + 4)[0]
            vals.append(d[vso:vso+vsl].decode('utf-8', errors='replace'))
        entries[key] = vals
    return entries

def main():
    print("Step 1: Restore pure NAER bins")
    restore_naer_bins()

    print("\nStep 2: Load wiki entities + NER freq")
    with open(WIKI_ENTITIES) as f:
        wiki_domains = json.load(f)
    ner_freq = load_ner_freq()
    print(f"  NER freq table: {len(ner_freq):,} entities")

    print(f"\nStep 3: Filter wiki entities (freq >= {FREQ_THRESHOLD}, clean keys)")
    for domain, entities in wiki_domains.items():
        before = len(entities)
        filtered = [e for e in entities
                    if _is_clean_key(e) and len(e) >= 3 and ner_freq.get(e, 0) >= FREQ_THRESHOLD]
        wiki_domains[domain] = filtered
        print(f"  {domain}: {before:,} → {len(filtered):,}")

    print("\nStep 4: Merge and rebuild bins")
    for domain, fname in DOMAIN_FILES.items():
        binpath = RES / f"{fname}.bin"
        naer = load_naer_terms(binpath)
        wiki_entities = wiki_domains.get(domain, [])

        # Add wiki entities as prefix-expansion entries
        for entity in wiki_entities:
            for plen in range(2, len(entity)):
                prefix = entity[:plen]
                suffix = entity[plen:]
                if prefix not in naer:
                    naer[prefix] = []
                if suffix not in naer[prefix] and len(naer[prefix]) < 8:
                    naer[prefix].append(suffix)

        build_wbmm({k: v for k, v in naer.items() if len(k) >= 2}, str(binpath))
        print(f"  {fname}: {len(naer):,} keys, +{len(wiki_entities):,} wiki")

    print("\nDone!")

if __name__ == "__main__":
    main()
