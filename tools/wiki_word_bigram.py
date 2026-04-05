#!/usr/bin/env python3
"""
詞級 bigram pipeline：用 ckip_mlx_c (C++ MLX) 斷詞，統計詞→詞共現。
給 iOS 版聯想輸入用。

用法: python3 tools/wiki_word_bigram.py
輸出: data/word_bigram.json
"""
import ctypes, json, os, time
from ctypes import c_char_p, c_int, c_int32, c_void_p, POINTER, Structure
from pathlib import Path
from collections import Counter, defaultdict
from tqdm import tqdm

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
OUT = DATA / "word_bigram.json"

CKIP_LIB = "/Users/fl/Python/ckip_mlx_c/libckip_bert.dylib"
CKIP_MODELS = os.path.expanduser("~/Python/ckip_mlx/models")

MIN_FREQ = 10
TOP_K = 5
BATCH_SIZE = 8


class WsResult(Structure):
    _fields_ = [("words", POINTER(c_char_p)), ("num_words", c_int)]

class PosResult(Structure):
    _fields_ = [("words", POINTER(c_char_p)), ("tags", POINTER(c_char_p)), ("num_words", c_int)]

class NerResult(Structure):
    _fields_ = [("texts", POINTER(c_char_p)), ("types", POINTER(c_char_p)),
                 ("starts", POINTER(c_int)), ("num_entities", c_int)]

class CkipResult(Structure):
    _fields_ = [("ws", POINTER(WsResult)), ("pos", POINTER(PosResult)),
                 ("ner", POINTER(NerResult)), ("num_sentences", c_int),
                 ("error_code", c_int32), ("error_msg", c_char_p)]


def load_ckip():
    lib = ctypes.CDLL(CKIP_LIB)
    lib.ckip_load.restype = c_void_p
    lib.ckip_load.argtypes = [c_char_p]
    lib.ckip_analyze.restype = CkipResult
    lib.ckip_analyze.argtypes = [c_void_p, POINTER(c_char_p), c_int]
    lib.ckip_result_free.argtypes = [POINTER(CkipResult)]
    lib.ckip_free.argtypes = [c_void_p]
    handle = lib.ckip_load(CKIP_MODELS.encode())
    return lib, handle


def tokenize_batch(lib, handle, lines):
    """Tokenize using ckip_analyze, extract WS results."""
    n = len(lines)
    arr = (c_char_p * n)(*(l.encode('utf-8') for l in lines))
    r = lib.ckip_analyze(handle, arr, n)
    results = []
    if r.error_code == 0:
        for i in range(r.num_sentences):
            w = r.ws[i]
            words = [w.words[j].decode('utf-8') for j in range(w.num_words)
                     if len(w.words[j].decode('utf-8')) >= 2]
            results.append(words)
    lib.ckip_result_free(ctypes.byref(r))
    while len(results) < n:
        results.append([])
    return results


def main():
    t0 = time.time()

    print(f"[1/4] 載入 ckip_mlx_c...")
    lib, handle = load_ckip()
    print(f"  OK ({time.time()-t0:.1f}s)")

    print(f"[2/4] 讀取 wiki_clean.txt...")
    lines = []
    with open(WIKI, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if len(line) >= 4:
                lines.append(line)
    print(f"  {len(lines):,} lines ({time.time()-t0:.0f}s)")

    print(f"[3/4] ckip 斷詞 + 統計詞級 bigram (batch={BATCH_SIZE})...")
    word_bigram = Counter()
    errors = 0
    start_line = 0

    # Resume from checkpoint
    ckpt_path = DATA / "word_bigram_ckpt.json"
    if ckpt_path.exists():
        with open(ckpt_path) as f:
            ckpt = json.load(f)
        start_line = ckpt["line"]
        word_bigram = Counter({tuple(k.split("\t")): v for k, v in ckpt["bigrams"].items()})
        print(f"  ⏩ 從 checkpoint 續跑: line {start_line:,}, {len(word_bigram):,} bigrams")

    for i in tqdm(range(start_line, len(lines), BATCH_SIZE),
                  initial=start_line // BATCH_SIZE,
                  total=(len(lines) + BATCH_SIZE - 1) // BATCH_SIZE,
                  desc="斷詞", unit="batch"):
        batch = lines[i:i+BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1

        try:
            tokenized = tokenize_batch(lib, handle, batch)
            for words in tokenized:
                for j in range(len(words) - 1):
                    word_bigram[(words[j], words[j+1])] += 1
        except Exception as e:
            errors += 1
            if errors <= 5:
                tqdm.write(f"  batch {batch_num} error: {e}")

        # Checkpoint every 50000 batches
        if batch_num % 50000 == 0:
            ckpt_data = {
                "line": i + len(batch),
                "bigrams": {f"{k[0]}\t{k[1]}": v for k, v in word_bigram.items()}
            }
            with open(ckpt_path, 'w') as f:
                json.dump(ckpt_data, f, ensure_ascii=False)
            tqdm.write(f"  💾 checkpoint saved ({len(word_bigram):,} bigrams)")

    # Final progress
    elapsed = time.time() - t0
    print(f"  總 bigram: {len(word_bigram):,}, errors: {errors} ({elapsed:.0f}s)")
    # Remove checkpoint on completion
    if ckpt_path.exists():
        ckpt_path.unlink()

    print(f"[4/4] 建 word_bigram.json (freq>={MIN_FREQ}, top {TOP_K})...")
    grouped = defaultdict(list)
    for (w1, w2), freq in word_bigram.items():
        if freq >= MIN_FREQ:
            grouped[w1].append((w2, freq))

    result = {}
    for w, pairs in grouped.items():
        pairs.sort(key=lambda x: x[1], reverse=True)
        result[w] = [w2 for w2, _ in pairs[:TOP_K]]

    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False)

    sz = os.path.getsize(OUT)
    print(f"  {len(result):,} entries, {sz/1e6:.1f} MB")
    print(f"  完成 ({time.time()-t0:.0f}s)")

    for w in ['研究', '臺灣', '中國', '美國', '大學', '政府', '電影', '音樂', '量子', '共產黨']:
        print(f"  {w} → {result.get(w, [])}")

    lib.ckip_free(handle)


if __name__ == '__main__':
    main()
