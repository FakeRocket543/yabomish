#!/usr/bin/env python3
"""
POC: 用 wiki 語料訓練 char embedding，驗證能否取代 n-gram 做候選排序。

1. 從 wiki_clean.txt 建 char-level skip-gram 訓練資料
2. 用 PyTorch 訓練 128 維 char embedding
3. 比較 embedding cosine similarity vs bigram freq 的排序品質
4. 測試記憶體用量和查詢延遲
"""
import torch
import torch.nn as nn
import numpy as np
import json, time, os, random
from pathlib import Path
from collections import Counter

DATA = Path(__file__).resolve().parent.parent / "data"
RES = Path(__file__).resolve().parent.parent / "YabomishIM" / "Resources"
WIKI = DATA / "wiki_work" / "wiki_clean.txt"

EMBED_DIM = 128
WINDOW = 3
MIN_FREQ = 20
NEG_SAMPLES = 5
BATCH_SIZE = 4096
EPOCHS = 3
LR = 0.01
MAX_LINES = 500_000  # sample for speed

# ── Step 1: Build vocabulary ──
print("[1/5] 建詞彙表...")
t0 = time.time()
char_freq = Counter()
lines = []
with open(WIKI, encoding='utf-8') as f:
    for i, line in enumerate(f):
        line = line.strip()
        if len(line) < 4:
            continue
        for ch in line:
            char_freq[ch] += 1
        lines.append(line)
        if len(lines) >= MAX_LINES:
            break

# Filter by min freq
vocab = {ch: idx+1 for idx, (ch, freq) in enumerate(char_freq.most_common()) if freq >= MIN_FREQ}
vocab['<UNK>'] = 0
idx2char = {v: k for k, v in vocab.items()}
VOCAB_SIZE = len(vocab)
print(f"  {len(lines):,} lines, {VOCAB_SIZE:,} chars ({time.time()-t0:.1f}s)")

# Subsampling probabilities (frequent chars downsampled)
total = sum(char_freq.values())
freq_ratio = {ch: char_freq[ch]/total for ch in vocab if ch != '<UNK>'}
subsample = {ch: max(0, 1 - np.sqrt(1e-5 / freq_ratio[ch])) for ch in freq_ratio}

# ── Step 2: Generate skip-gram pairs ──
print("[2/5] 生成 skip-gram pairs...")
pairs = []
for line in lines:
    indices = [vocab.get(ch, 0) for ch in line]
    for i, center in enumerate(indices):
        if center == 0:
            continue
        ch = idx2char[center]
        if random.random() < subsample.get(ch, 0):
            continue
        start = max(0, i - WINDOW)
        end = min(len(indices), i + WINDOW + 1)
        for j in range(start, end):
            if j == i or indices[j] == 0:
                continue
            pairs.append((center, indices[j]))

random.shuffle(pairs)
pairs = pairs[:5_000_000]  # cap for speed
print(f"  {len(pairs):,} pairs ({time.time()-t0:.1f}s)")

# Negative sampling table
freq_arr = np.array([char_freq.get(idx2char.get(i, ''), 1) for i in range(VOCAB_SIZE)], dtype=np.float32)
freq_arr = freq_arr ** 0.75
neg_table = freq_arr / freq_arr.sum()

# ── Step 3: Train Skip-gram with Negative Sampling ──
print("[3/5] 訓練 embedding...")

class SkipGram(nn.Module):
    def __init__(self, vocab_size, embed_dim):
        super().__init__()
        self.center = nn.Embedding(vocab_size, embed_dim)
        self.context = nn.Embedding(vocab_size, embed_dim)
        nn.init.xavier_uniform_(self.center.weight)
        nn.init.zeros_(self.context.weight)

    def forward(self, c, pos, neg):
        c_emb = self.center(c)                    # (B, D)
        p_emb = self.context(pos)                  # (B, D)
        n_emb = self.context(neg)                  # (B, K, D)
        pos_score = torch.sum(c_emb * p_emb, dim=1)  # (B,)
        neg_score = torch.bmm(n_emb, c_emb.unsqueeze(2)).squeeze(2)  # (B, K)
        pos_loss = -torch.log(torch.sigmoid(pos_score) + 1e-7).mean()
        neg_loss = -torch.log(torch.sigmoid(-neg_score) + 1e-7).mean()
        return pos_loss + neg_loss

device = torch.device('mps' if torch.backends.mps.is_available() else 'cpu')
model = SkipGram(VOCAB_SIZE, EMBED_DIM).to(device)
optimizer = torch.optim.Adam(model.parameters(), lr=LR)

pairs_t = torch.tensor(pairs, dtype=torch.long)
for epoch in range(EPOCHS):
    perm = torch.randperm(len(pairs_t))
    total_loss = 0
    n_batches = 0
    for i in range(0, len(pairs_t), BATCH_SIZE):
        batch = pairs_t[perm[i:i+BATCH_SIZE]]
        if len(batch) < 2:
            continue
        centers = batch[:, 0].to(device)
        positives = batch[:, 1].to(device)
        # Negative samples
        neg_idx = torch.multinomial(torch.from_numpy(neg_table), len(batch) * NEG_SAMPLES, replacement=True)
        negatives = neg_idx.reshape(len(batch), NEG_SAMPLES).to(device)

        loss = model(centers, positives, negatives)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
        n_batches += 1

    print(f"  Epoch {epoch+1}/{EPOCHS}: loss={total_loss/n_batches:.4f} ({time.time()-t0:.0f}s)")

# ── Step 4: Extract and save embeddings ──
print("[4/5] 儲存 embedding...")
embeddings = model.center.weight.detach().cpu().numpy()

# Save as numpy binary (mmap-friendly)
emb_path = DATA / "char_embedding.npy"
vocab_path = DATA / "char_embedding_vocab.json"
np.save(str(emb_path), embeddings.astype(np.float16))
with open(vocab_path, 'w') as f:
    json.dump(vocab, f, ensure_ascii=False)

print(f"  {emb_path}: {os.path.getsize(emb_path)/1e6:.1f} MB")
print(f"  {VOCAB_SIZE} chars × {EMBED_DIM} dim = {embeddings.shape}")

# ── Step 5: 驗證 — 比較 embedding vs bigram 的排序品質 ──
print("\n[5/5] 驗證排序品質...")

# Load bigram for comparison
with open(RES / 'bigram_suggest.json') as f:
    bigram_suggest = json.load(f)

def cosine_sim(a, b):
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8)

def top_similar(char, topk=10):
    if char not in vocab:
        return []
    idx = vocab[char]
    vec = embeddings[idx]
    sims = embeddings @ vec / (np.linalg.norm(embeddings, axis=1) * np.linalg.norm(vec) + 1e-8)
    top_idx = np.argsort(sims)[::-1][1:topk+1]
    return [(idx2char.get(i, '?'), float(sims[i])) for i in top_idx]

# Test cases
test_chars = ['研', '臺', '中', '毛', '物', '學', '不', '的']
print("\n  Embedding 最相似字 vs Bigram 建議:")
print(f"  {'字':>4s}  {'Embedding top5':30s}  {'Bigram top3':20s}")
print(f"  {'─'*4}  {'─'*30}  {'─'*20}")
for ch in test_chars:
    emb_top = top_similar(ch, 5)
    emb_str = ' '.join(f"{c}({s:.2f})" for c, s in emb_top)
    bg_str = ' '.join(bigram_suggest.get(ch, []))
    print(f"  {ch:>4s}  {emb_str:30s}  {bg_str:20s}")

# Latency test
print("\n  延遲測試:")
vec = embeddings[vocab.get('研', 0)]
t1 = time.time()
for _ in range(10000):
    sims = embeddings @ vec
    top5 = np.argsort(sims)[::-1][:5]
t2 = time.time()
print(f"  Brute-force cosine (全表): {(t2-t1)/10000*1000:.2f} ms/query")

# Memory
print(f"\n  記憶體: {embeddings.nbytes/1e6:.1f} MB (float32), {embeddings.astype(np.float16).nbytes/1e6:.1f} MB (float16)")
print(f"  對比: bigram_boost.json = {os.path.getsize(RES/'bigram_boost.json')/1e6:.1f} MB")
print(f"         trigram_suggest.json = {os.path.getsize(RES/'trigram_suggest.json')/1e6:.1f} MB")
