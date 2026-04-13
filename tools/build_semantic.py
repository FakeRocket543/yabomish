#!/usr/bin/env python3
"""Build terms_semantic.bin — 近似義詞庫.

分兩步執行（避免 MLX + FAISS 同進程 segfault）：
  Step 1: python3 tools/build_semantic.py encode   → /tmp/semantic_vecs.npz
  Step 2: python3 tools/build_semantic.py build [--threshold 0.65] [--check]
"""
import sys, os, struct, argparse, time, json
from pathlib import Path
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

RES = Path(__file__).resolve().parent.parent / "YabomishIM" / "Resources"
HLS = Path(__file__).resolve().parent.parent.parent / "hls"
DST = RES / "terms_semantic.bin"
CACHE = Path("/tmp/semantic_vecs.npz")

GENERAL_BINS = [
    "chengyu", "phrases", "ner_phrases",
    "terms_kautian", "terms_hakka", "terms_korean", "terms_xiehouyu",
    "terms_jingjing", "terms_cn_slang", "terms_placename", "terms_ttg",
    "yoji",
]


def extract_values_from_wbmm(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"WBMM":
        return set()
    kc = struct.unpack_from("<I", d, 4)[0]
    ki = struct.unpack_from("<I", d, 8)[0]
    vi = struct.unpack_from("<I", d, 12)[0]
    terms = set()
    for i in range(kc):
        eo = ki + i * 12
        so = struct.unpack_from("<I", d, eo)[0]
        sl = struct.unpack_from("<H", d, eo + 4)[0]
        key = d[so : so + sl].decode("utf-8", errors="replace")
        vs = struct.unpack_from("<I", d, eo + 6)[0]
        vc = struct.unpack_from("<H", d, eo + 10)[0]
        for j in range(vc):
            vo = vi + (vs + j) * 6
            vso = struct.unpack_from("<I", d, vo)[0]
            vsl = struct.unpack_from("<H", d, vo + 4)[0]
            val = d[vso : vso + vsl].decode("utf-8", errors="replace")
            full = key + val
            if 2 <= len(full) <= 8:
                terms.add(full)
    return terms


def extract_all_terms():
    all_terms = set()
    for name in GENERAL_BINS:
        p = RES / f"{name}.bin"
        if not p.exists():
            print(f"  skip {name}.bin")
            continue
        terms = extract_values_from_wbmm(str(p))
        print(f"  {name}.bin: {len(terms):,}")
        all_terms |= terms
    return sorted(all_terms)


def cmd_encode():
    """Step 1: Extract terms + encode with Qwen3-Embed-0.6B → save to cache."""
    print("=== Step 1: Extract terms ===")
    terms = extract_all_terms()
    print(f"Total: {len(terms):,}")

    print("\n=== Step 2: Encode with Qwen3-Embed-0.6B (MLX) ===")
    sys.path.insert(0, str(HLS))
    from embed import EmbeddingModel

    em = EmbeddingModel(str(HLS / "models" / "qwen3-embed-0.6b"))
    _ = em.encode("warmup")

    batch_size = 256
    all_vecs = []
    t0 = time.time()
    for i in range(0, len(terms), batch_size):
        batch = terms[i : i + batch_size]
        vecs = em.encode(batch)
        all_vecs.append(np.array(vecs.tolist(), dtype=np.float32))
        done = i + len(batch)
        if done % (batch_size * 10) < batch_size:
            elapsed = time.time() - t0
            rate = done / elapsed
            eta = (len(terms) - done) / rate if rate > 0 else 0
            print(f"  {done:,}/{len(terms):,} ({rate:.0f}/s, ETA {eta:.0f}s)")

    all_vecs = np.concatenate(all_vecs, axis=0)
    elapsed = time.time() - t0
    print(f"  Done: {all_vecs.shape} in {elapsed:.1f}s")

    np.savez_compressed(str(CACHE), terms=np.array(terms, dtype=object), vecs=all_vecs)
    print(f"  Saved to {CACHE} ({CACHE.stat().st_size / 1e6:.1f} MB)")


def cmd_build(threshold=0.65, check=False):
    """Step 2: FAISS search + build WBMM (separate process, no MLX)."""
    import faiss
    from build_wbmm import build_wbmm

    print(f"=== Loading cache from {CACHE} ===")
    data = np.load(str(CACHE), allow_pickle=True)
    terms = list(data["terms"])
    vecs = data["vecs"]
    print(f"  {len(terms):,} terms, {vecs.shape}")

    print(f"\n=== FAISS top-8 neighbors (threshold={threshold}) ===")
    index = faiss.IndexFlatIP(vecs.shape[1])
    index.add(vecs)
    D, I = index.search(vecs, 9)

    entries = {}
    for i, term in enumerate(terms):
        neighbors = []
        for j in range(1, 9):
            if D[i][j] >= threshold and terms[I[i][j]] != term:
                neighbors.append(terms[I[i][j]])
        if neighbors:
            entries[term] = neighbors

    print(f"  Terms with neighbors: {len(entries):,} / {len(terms):,}")

    if check:
        print("\n=== Quality check ===")
        import random
        random.seed(42)
        samples = random.sample(list(entries.keys()), min(40, len(entries)))
        for term in sorted(samples):
            idx = terms.index(term)
            nbrs = []
            for j in range(1, 6):
                if D[idx][j] >= threshold:
                    nbrs.append(f"{terms[I[idx][j]]}({D[idx][j]:.2f})")
            print(f"  {term} → {', '.join(nbrs)}")
        return

    print(f"\n=== Build terms_semantic.bin ===")
    build_wbmm(entries, str(DST))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cmd", choices=["encode", "build"], help="encode=MLX embedding, build=FAISS+WBMM")
    parser.add_argument("--threshold", type=float, default=0.65)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.cmd == "encode":
        cmd_encode()
    else:
        cmd_build(threshold=args.threshold, check=args.check)


if __name__ == "__main__":
    main()
