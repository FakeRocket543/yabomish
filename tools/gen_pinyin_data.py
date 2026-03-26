#!/usr/bin/env python3
"""從 zhuyin_data.json 生成 pinyin_data.json（拼音→字 對照表）"""
import json, os

# 注音聲母→拼音
INITIALS = {
    'ㄅ': 'b', 'ㄆ': 'p', 'ㄇ': 'm', 'ㄈ': 'f',
    'ㄉ': 'd', 'ㄊ': 't', 'ㄋ': 'n', 'ㄌ': 'l',
    'ㄍ': 'g', 'ㄎ': 'k', 'ㄏ': 'h',
    'ㄐ': 'j', 'ㄑ': 'q', 'ㄒ': 'x',
    'ㄓ': 'zh', 'ㄔ': 'ch', 'ㄕ': 'sh', 'ㄖ': 'r',
    'ㄗ': 'z', 'ㄘ': 'c', 'ㄙ': 's',
}

# 注音韻母→拼音（含介音組合）
FINALS = {
    'ㄚ': 'a', 'ㄛ': 'o', 'ㄜ': 'e', 'ㄝ': 'ê',
    'ㄞ': 'ai', 'ㄟ': 'ei', 'ㄠ': 'ao', 'ㄡ': 'ou',
    'ㄢ': 'an', 'ㄣ': 'en', 'ㄤ': 'ang', 'ㄥ': 'eng', 'ㄦ': 'er',
    # ㄧ 系列
    'ㄧ': 'i', 'ㄧㄚ': 'ia', 'ㄧㄛ': 'io', 'ㄧㄝ': 'ie',
    'ㄧㄞ': 'iai', 'ㄧㄠ': 'iao', 'ㄧㄡ': 'iu',
    'ㄧㄢ': 'ian', 'ㄧㄣ': 'in', 'ㄧㄤ': 'iang', 'ㄧㄥ': 'ing',
    # ㄨ 系列
    'ㄨ': 'u', 'ㄨㄚ': 'ua', 'ㄨㄛ': 'uo', 'ㄨㄞ': 'uai', 'ㄨㄟ': 'ui',
    'ㄨㄢ': 'uan', 'ㄨㄣ': 'un', 'ㄨㄤ': 'uang', 'ㄨㄥ': 'ong',
    # ㄩ 系列
    'ㄩ': 'ü', 'ㄩㄝ': 'üe', 'ㄩㄢ': 'üan', 'ㄩㄣ': 'ün', 'ㄩㄥ': 'iong',
}

# 聲調符號→數字
TONES = {'': '1', 'ˊ': '2', 'ˇ': '3', 'ˋ': '4', '˙': '5'}

def zhuyin_to_pinyin(zy: str) -> str | None:
    """將一個注音音節轉為拼音（帶數字聲調）"""
    # 處理聲調
    tone = '1'
    if zy.startswith('˙'):
        tone = '5'
        zy = zy[1:]
    elif zy.endswith('ˊ'):
        tone = '2'; zy = zy[:-1]
    elif zy.endswith('ˇ'):
        tone = '3'; zy = zy[:-1]
    elif zy.endswith('ˋ'):
        tone = '4'; zy = zy[:-1]

    # 分離聲母
    initial = ''
    for k in sorted(INITIALS.keys(), key=len, reverse=True):
        if zy.startswith(k):
            initial = INITIALS[k]
            zy = zy[len(k):]
            break

    # 韻母
    if not zy:
        # 空韻母：ㄓㄔㄕㄖㄗㄘㄙ 獨立成音
        if initial in ('zh', 'ch', 'sh', 'r', 'z', 'c', 's'):
            return initial + 'i' + tone
        return None

    # 嘗試最長匹配韻母
    final = ''
    for k in sorted(FINALS.keys(), key=len, reverse=True):
        if zy == k:
            final = FINALS[k]
            break
    if not final:
        return None

    # 拼音拼寫規則調整
    if not initial:
        # 無聲母
        if final == 'i':
            final = 'yi'
        elif final.startswith('i'):
            final = 'y' + final[1:]
        elif final == 'u':
            final = 'wu'
        elif final.startswith('u'):
            final = 'w' + final[1:]
        elif final == 'ü':
            final = 'yu'
        elif final.startswith('ü'):
            final = 'yu' + final[1:]
        elif final == 'ong':
            final = 'weng'
        elif final == 'iong':
            final = 'yong'
    else:
        # j/q/x + ü → u
        if initial in ('j', 'q', 'x'):
            final = final.replace('ü', 'u')

    return initial + final + tone


def main():
    src = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'zhuyin_data.json')
    with open(src) as f:
        data = json.load(f)

    z2c = data['zhuyin_to_chars']
    pinyin_to_chars: dict[str, list[str]] = {}
    failed = []

    for zy, chars in z2c.items():
        py = zhuyin_to_pinyin(zy)
        if py is None:
            failed.append(zy)
            continue
        if py in pinyin_to_chars:
            # 合併（去重保序）
            existing = set(pinyin_to_chars[py])
            for c in chars:
                if c not in existing:
                    pinyin_to_chars[py].append(c)
                    existing.add(c)
        else:
            pinyin_to_chars[py] = list(chars)

    if failed:
        print(f"⚠️  {len(failed)} 個注音無法轉換: {failed[:10]}...")

    dst = os.path.join(os.path.dirname(__file__), '..', 'YabomishIM', 'Resources', 'pinyin_data.json')
    with open(dst, 'w', encoding='utf-8') as f:
        json.dump({'pinyin_to_chars': pinyin_to_chars}, f, ensure_ascii=False)

    print(f"✅ 生成 {len(pinyin_to_chars)} 個拼音音節 → {dst}")


if __name__ == '__main__':
    main()
