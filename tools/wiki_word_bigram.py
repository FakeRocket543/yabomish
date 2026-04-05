#!/usr/bin/env python3
"""
詞級 bigram pipeline：用 Apple NLTokenizer 斷詞，統計詞→詞共現。
給 iOS 版聯想輸入用。

用法: python3 tools/wiki_word_bigram.py
輸出: data/word_bigram.json (prev_word → [next_word1, next_word2, ...])
"""
import subprocess, json, tempfile, os
from pathlib import Path
from collections import Counter

DATA = Path(__file__).resolve().parent.parent / "data"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"
OUT = DATA / "word_bigram.json"

MIN_FREQ = 10
TOP_K = 5
BATCH_SIZE = 5000  # lines per Swift batch

def tokenize_batch(lines: list[str]) -> list[list[str]]:
    """Call Swift to tokenize lines using NLTokenizer."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False, encoding='utf-8') as f:
        f.write('\n'.join(lines))
        tmp = f.name
    
    swift_code = f'''
import Foundation
import NaturalLanguage

let text = try! String(contentsOfFile: "{tmp}", encoding: .utf8)
let tokenizer = NLTokenizer(unit: .word)
tokenizer.setLanguage(.traditionalChinese)

for line in text.components(separatedBy: "\\n") {{
    guard !line.isEmpty else {{ print(""); continue }}
    tokenizer.string = line
    var words: [String] = []
    tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) {{ range, _ in
        let w = String(line[range])
        if w.count >= 2 {{ words.append(w) }}  // skip single chars
        return true
    }}
    print(words.joined(separator: "\\t"))
}}
'''
    with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as sf:
        sf.write(swift_code)
        swift_tmp = sf.name
    
    result = subprocess.run(['swift', swift_tmp], capture_output=True, text=True, timeout=300)
    os.unlink(tmp)
    os.unlink(swift_tmp)
    
    tokenized = []
    for line in result.stdout.strip().split('\n'):
        if line:
            tokenized.append(line.split('\t'))
        else:
            tokenized.append([])
    return tokenized


def main():
    import time
    t0 = time.time()
    
    print(f"[1/3] 讀取 wiki_clean.txt...")
    lines = []
    with open(WIKI, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if len(line) >= 4:
                lines.append(line)
    print(f"  {len(lines):,} lines ({time.time()-t0:.0f}s)")
    
    print(f"[2/3] NLTokenizer 斷詞 + 統計詞級 bigram...")
    word_bigram = Counter()
    total_batches = (len(lines) + BATCH_SIZE - 1) // BATCH_SIZE
    
    for i in range(0, len(lines), BATCH_SIZE):
        batch = lines[i:i+BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1
        
        try:
            tokenized = tokenize_batch(batch)
        except Exception as e:
            print(f"  batch {batch_num} error: {e}, skipping")
            continue
        
        for words in tokenized:
            for j in range(len(words) - 1):
                word_bigram[(words[j], words[j+1])] += 1
        
        if batch_num % 20 == 0 or batch_num == total_batches:
            print(f"  batch {batch_num}/{total_batches}, bigrams: {len(word_bigram):,} ({time.time()-t0:.0f}s)")
    
    print(f"  總 bigram: {len(word_bigram):,}")
    
    print(f"[3/3] 建 word_bigram.json (freq>={MIN_FREQ}, top {TOP_K})...")
    # Group by prev_word
    from collections import defaultdict
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
    
    # Sample
    for w in ['研究', '臺灣', '中國', '美國', '大學', '政府', '電影', '音樂']:
        print(f"  {w} → {result.get(w, [])}")


if __name__ == '__main__':
    main()
