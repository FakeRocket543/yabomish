#!/usr/bin/env python3
"""
維基中文語料 → ckip_mlx NER → 實體抽取 pipeline

分批處理 wiki_clean.txt，每 30 萬段一個批次檔，
最後合併統計所有實體頻次，輸出 CSV + Parquet。

用法：
  python3 tools/wiki_ner_pipeline.py              # 跑 NER（自動續跑）
  python3 tools/wiki_ner_pipeline.py --merge-only  # 只合併統計
"""
import argparse, json, os, time
from collections import Counter
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent.parent
WORK = BASE / "data" / "wiki_work"
OUT = BASE / "data"
CLEAN_FILE = WORK / "wiki_clean.txt"
NER_DIR = WORK / "ner_batches"

BATCH_SIZE = 8
MAX_LEN = 512
NER_BATCH_LINES = 300000

# NER 標籤 (BIES scheme)
ID2LABEL = {
    0: "O",
    1: "B-CARDINAL", 2: "B-DATE", 3: "B-EVENT", 4: "B-FAC", 5: "B-GPE",
    6: "B-LANGUAGE", 7: "B-LAW", 8: "B-LOC", 9: "B-MONEY", 10: "B-NORP",
    11: "B-ORDINAL", 12: "B-ORG", 13: "B-PERCENT", 14: "B-PERSON",
    15: "B-PRODUCT", 16: "B-QUANTITY", 17: "B-TIME", 18: "B-WORK_OF_ART",
    19: "I-CARDINAL", 20: "I-DATE", 21: "I-EVENT", 22: "I-FAC", 23: "I-GPE",
    24: "I-LANGUAGE", 25: "I-LAW", 26: "I-LOC", 27: "I-MONEY", 28: "I-NORP",
    29: "I-ORDINAL", 30: "I-ORG", 31: "I-PERCENT", 32: "I-PERSON",
    33: "I-PRODUCT", 34: "I-QUANTITY", 35: "I-TIME", 36: "I-WORK_OF_ART",
    37: "E-CARDINAL", 38: "E-DATE", 39: "E-EVENT", 40: "E-FAC", 41: "E-GPE",
    42: "E-LANGUAGE", 43: "E-LAW", 44: "E-LOC", 45: "E-MONEY", 46: "E-NORP",
    47: "E-ORDINAL", 48: "E-ORG", 49: "E-PERCENT", 50: "E-PERSON",
    51: "E-PRODUCT", 52: "E-QUANTITY", 53: "E-TIME", 54: "E-WORK_OF_ART",
    55: "S-CARDINAL", 56: "S-DATE", 57: "S-EVENT", 58: "S-FAC", 59: "S-GPE",
    60: "S-LANGUAGE", 61: "S-LAW", 62: "S-LOC", 63: "S-MONEY", 64: "S-NORP",
    65: "S-ORDINAL", 66: "S-ORG", 67: "S-PERCENT", 68: "S-PERSON",
    69: "S-PRODUCT", 70: "S-QUANTITY", 71: "S-TIME", 72: "S-WORK_OF_ART",
}


def _load_ner_model():
    import sys as _sys
    CKIP_MLX = Path("/Users/fl/Python/ckip_mlx")
    _sys.path.insert(0, str(CKIP_MLX))
    import mlx.core as mx
    from bert_mlx import BertForTokenClassification

    ner_dir = CKIP_MLX / "models" / "ner"
    with open(ner_dir / "config.json") as f:
        config = json.load(f)
    model = BertForTokenClassification(config)
    model.load_weights(str(ner_dir / "weights.safetensors"))
    mx.eval(model.parameters())

    vocab = {}
    with open(ner_dir / "vocab.txt") as f:
        for i, line in enumerate(f):
            vocab[line.strip()] = i
    unk_id = vocab.get("[UNK]", 100)
    return model, vocab, unk_id, mx


def _ner_batch(texts, model, vocab, unk_id, mx):
    """對一批文字做 NER，回傳每段的實體列表 [(entity, type), ...]"""
    max_len = max(len(t) for t in texts) + 2
    batch_ids, batch_mask = [], []
    for t in texts:
        ids = [101] + [vocab.get(ch, unk_id) for ch in t] + [102]
        pad = max_len - len(ids)
        batch_ids.append(ids + [0] * pad)
        batch_mask.append([1] * len(ids) + [0] * pad)
    out = model(mx.array(batch_ids), attention_mask=mx.array(batch_mask))
    mx.eval(out)
    preds_batch = mx.argmax(out, axis=-1).tolist()

    all_entities = []
    for idx, t in enumerate(texts):
        preds = preds_batch[idx]
        entities = []
        cur_entity, cur_type = "", ""
        for i, ch in enumerate(t):
            label = ID2LABEL.get(preds[i + 1], "O")
            if label == "O":
                if cur_entity:
                    entities.append((cur_entity, cur_type))
                    cur_entity, cur_type = "", ""
            elif label.startswith("S-"):
                if cur_entity:
                    entities.append((cur_entity, cur_type))
                entities.append((ch, label[2:]))
                cur_entity, cur_type = "", ""
            elif label.startswith("B-"):
                if cur_entity:
                    entities.append((cur_entity, cur_type))
                cur_entity, cur_type = ch, label[2:]
            elif label.startswith("I-"):
                cur_entity += ch
            elif label.startswith("E-"):
                cur_entity += ch
                entities.append((cur_entity, cur_type))
                cur_entity, cur_type = "", ""
        if cur_entity:
            entities.append((cur_entity, cur_type))
        all_entities.append(entities)
    return all_entities


def step_ner():
    NER_DIR.mkdir(parents=True, exist_ok=True)

    print("  讀取 wiki_clean.txt 並切段...")
    segments = []
    with open(CLEAN_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                for i in range(0, len(line), MAX_LEN):
                    seg = line[i:i + MAX_LEN]
                    if seg:
                        segments.append(seg)

    total = len(segments)
    num_batches = (total + NER_BATCH_LINES - 1) // NER_BATCH_LINES
    print(f"  共 {total:,} 段, 分 {num_batches} 批 (每批 {NER_BATCH_LINES:,})")

    # 找已完成批次
    done_batches = set()
    for p in sorted(NER_DIR.glob("ner_batch_*.jsonl")):
        idx = int(p.stem.split("_")[-1])
        with open(p, encoding="utf-8") as f:
            lines = sum(1 for _ in f)
        start = idx * NER_BATCH_LINES
        expected = min(NER_BATCH_LINES, total - start)
        if lines == expected:
            done_batches.add(idx)
            print(f"    批次 {idx:03d} 已完成 ({lines:,} 行), 跳過")
        else:
            print(f"    批次 {idx:03d} 不完整 ({lines:,}/{expected:,}), 將重跑")

    remaining = [i for i in range(num_batches) if i not in done_batches]
    if not remaining:
        print("  所有批次已完成！")
        return

    print(f"  需處理 {len(remaining)} 批: {remaining}")
    print("  載入 ckip_mlx NER 模型...")
    model, vocab, unk_id, mx = _load_ner_model()
    _ner_batch(segments[:2], model, vocab, unk_id, mx)  # warmup

    for batch_idx in remaining:
        start = batch_idx * NER_BATCH_LINES
        end = min(start + NER_BATCH_LINES, total)
        batch_segs = segments[start:end]
        batch_file = NER_DIR / f"ner_batch_{batch_idx:03d}.jsonl"
        batch_total = len(batch_segs)

        print(f"\n  === 批次 {batch_idx:03d} ({start:,}~{end:,}, {batch_total:,} 段) ===")
        t0 = time.time()

        with open(batch_file, "w", encoding="utf-8") as out:
            for i in range(0, batch_total, BATCH_SIZE):
                batch = batch_segs[i:i + BATCH_SIZE]
                results = _ner_batch(batch, model, vocab, unk_id, mx)
                for entities in results:
                    # 每行一個 JSON: [[entity, type], ...]
                    out.write(json.dumps(entities, ensure_ascii=False) + "\n")
                done = min(i + BATCH_SIZE, batch_total)
                if done % 10000 < BATCH_SIZE:
                    elapsed = time.time() - t0
                    speed = done / elapsed if elapsed > 0 else 0
                    eta = (batch_total - done) / speed if speed > 0 else 0
                    print(f"    {done:,}/{batch_total:,} ({done * 100 // batch_total}%) "
                          f"{speed:.0f} seg/s, ETA {eta / 60:.0f}min")

        elapsed = time.time() - t0
        print(f"  批次 {batch_idx:03d} 完成: {batch_file.name} "
              f"({elapsed / 60:.1f}min, {batch_total / elapsed:.0f} seg/s)")


def step_merge():
    """合併所有批次，統計實體頻次，輸出 CSV + Parquet"""
    batch_files = sorted(NER_DIR.glob("ner_batch_*.jsonl"))
    if not batch_files:
        print("  ⚠️  找不到批次檔！")
        return

    print(f"  合併 {len(batch_files)} 個批次檔...")
    entity_counter = Counter()  # (entity, type) -> freq
    total_lines = 0

    for bf in batch_files:
        with open(bf, encoding="utf-8") as f:
            for line in f:
                total_lines += 1
                entities = json.loads(line)
                for ent, etype in entities:
                    if len(ent) >= 2:  # 過濾單字實體（雜訊多）
                        entity_counter[(ent, etype)] += 1
        print(f"    {bf.name}: 累計 {total_lines:,} 行, {len(entity_counter):,} 種實體")

    print(f"\n  總計: {total_lines:,} 行, {len(entity_counter):,} 種實體")

    # 輸出
    rows = [{"entity": e, "type": t, "freq": f}
            for (e, t), f in entity_counter.most_common()]
    df = pd.DataFrame(rows)
    df.to_csv(OUT / "wiki_ner_entities.csv", index=False, encoding="utf-8-sig")
    df.to_parquet(OUT / "wiki_ner_entities.parquet", index=False)
    print(f"  wiki_ner_entities: {len(df):,} rows")

    # 各類型統計
    print("\n  各類型實體數量:")
    for etype in sorted(df["type"].unique()):
        sub = df[df["type"] == etype]
        print(f"    {etype:15s}: {len(sub):>8,} 種, 總頻次 {sub['freq'].sum():>12,}")

    # 顯示前幾名
    for etype in ["PERSON", "ORG", "GPE", "LOC", "WORK_OF_ART"]:
        sub = df[df["type"] == etype].head(10)
        if len(sub):
            print(f"\n  Top {etype}:")
            print(sub.to_string(index=False))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--merge-only", action="store_true", help="只合併統計")
    args = parser.parse_args()

    if not args.merge_only:
        print("[1/2] NER 實體抽取（分批）...")
        step_ner()

    print("\n[2/2] 合併統計...")
    step_merge()
    print("\n✅ NER 完成！")


if __name__ == "__main__":
    main()
