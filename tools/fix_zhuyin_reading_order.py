#!/usr/bin/env python3
"""
修正 zhuyin_data.json 中 char_to_zhuyins 的讀音順序。

策略：
1. 以萌典版為基礎（讀音順序較合理）
2. 補入威注音獨有的字
3. 用 wiki 語料庫的注音候選字頻率來修正破音字的讀音順序
4. 同步更新 zhuyin_to_chars（確保一致性）
"""
import json, subprocess, sys
from pathlib import Path
from collections import defaultdict

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"


def load_moe_from_git():
    """從 git 歷史取萌典版 zhuyin_data.json"""
    r = subprocess.run(
        ["git", "show", "41d1a26:YabomishIM/Resources/zhuyin_data.json"],
        capture_output=True, text=True, cwd=BASE,
    )
    if r.returncode != 0:
        print(f"❌ git show failed: {r.stderr}")
        sys.exit(1)
    return json.loads(r.stdout)


def load_current():
    with open(RES / "zhuyin_data.json", encoding="utf-8") as f:
        return json.load(f)


def load_wiki_zhuyin_freq():
    """載入 wiki 語料庫的注音候選字頻率，用來推斷每個字在每個讀音下的使用頻率"""
    p = BASE / "data" / "wiki_zhuyin_candidates.csv"
    if not p.exists():
        return {}
    import csv
    # zhuyin,char,wiki_freq,effective_freq,is_poly,is_primary_reading
    char_reading_freq = {}  # {char: {zhuyin: freq}}
    with open(p, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            ch = row["char"]
            zy = row["zhuyin"]
            freq = int(row["wiki_freq"])
            if ch not in char_reading_freq:
                char_reading_freq[ch] = {}
            char_reading_freq[ch][zy] = freq
    return char_reading_freq


def reorder_readings(char, zhuyins, wiki_freq):
    """用 wiki 頻率重新排序一個字的讀音列表"""
    if len(zhuyins) <= 1:
        return zhuyins
    freq_map = wiki_freq.get(char, {})
    if not freq_map:
        return zhuyins  # 沒有語料資料，保持原順序
    return sorted(zhuyins, key=lambda zy: freq_map.get(zy, 0), reverse=True)


def rebuild_z2c(c2z):
    """從 char_to_zhuyins 重建 zhuyin_to_chars"""
    z2c = defaultdict(list)
    for char, zhuyins in c2z.items():
        for zy in zhuyins:
            z2c[zy].append(char)
    return dict(z2c)


def main():
    print("載入資料...")
    moe = load_moe_from_git()
    cur = load_current()
    wiki_freq = load_wiki_zhuyin_freq()

    c2z_moe = moe["char_to_zhuyins"]
    z2c_moe = moe["zhuyin_to_chars"]
    c2z_cur = cur["char_to_zhuyins"]

    print(f"  萌典: {len(c2z_moe)} 字")
    print(f"  威注音: {len(c2z_cur)} 字")
    print(f"  wiki 頻率: {len(wiki_freq)} 字")

    # 1. 以萌典為基礎
    c2z_new = dict(c2z_moe)

    # 2. 補入威注音獨有的字
    added = 0
    for char, zhuyins in c2z_cur.items():
        if char not in c2z_new:
            c2z_new[char] = zhuyins
            added += 1
    print(f"\n補入威注音獨有字: {added}")

    # 3. 用 wiki 頻率修正破音字讀音順序
    reordered = 0
    for char, zhuyins in c2z_new.items():
        if len(zhuyins) > 1:
            new_order = reorder_readings(char, zhuyins, wiki_freq)
            if new_order != zhuyins:
                c2z_new[char] = new_order
                reordered += 1

    print(f"修正讀音順序: {reordered} 個破音字")

    # 4. 重建 zhuyin_to_chars（用萌典的字順序為基礎，補入新字）
    z2c_new = defaultdict(list)
    # 先放萌典的順序
    for zy, chars in z2c_moe.items():
        z2c_new[zy] = list(chars)
    # 補入威注音獨有的注音→字對應
    for char, zhuyins in c2z_new.items():
        for zy in zhuyins:
            if char not in z2c_new[zy]:
                z2c_new[zy].append(char)
    z2c_new = dict(z2c_new)

    print(f"\n最終: {len(c2z_new)} 字, {len(z2c_new)} 個注音")

    # 驗證
    test = {
        "同": "ㄊㄨㄥˊ", "為": "ㄨㄟˊ", "大": "ㄉㄚˋ",
        "說": "ㄕㄨㄛ", "還": "ㄏㄞˊ", "樂": "ㄌㄜˋ",
    }
    print("\n驗證常見破音字:")
    for ch, expected in test.items():
        actual = c2z_new.get(ch, [])
        ok = actual[0] == expected if actual else False
        mark = "✅" if ok else "❌"
        print(f"  {mark} {ch}: {actual}")

    # 寫入
    out = {"zhuyin_to_chars": z2c_new, "char_to_zhuyins": c2z_new}
    with open(RES / "zhuyin_data.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"\n✅ 已寫入 {RES / 'zhuyin_data.json'}")

    # 重新生成 pinyin_data.json
    print("\n重新生成 pinyin_data.json...")
    subprocess.run([sys.executable, str(BASE / "tools" / "gen_pinyin_data.py")], cwd=BASE)


if __name__ == "__main__":
    main()
