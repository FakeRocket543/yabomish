#!/usr/bin/env python3
"""
Emoji CIN Patcher: 讀入嘸蝦米 .cin，為每個中文字的碼加上對應 emoji 候選。
資料來源: Unicode CLDR zh_Hant emoji annotations

用法:
  python3 tools/emoji_cin_patch.py input.cin output.cin
  python3 tools/emoji_cin_patch.py input.cin  # 輸出到 stdout
"""
import sys, json, os

DATA = os.path.join(os.path.dirname(__file__), '..', 'data', 'emoji_keywords.json')

def load_emoji_keywords():
    with open(DATA) as f:
        return json.load(f)  # emoji → [keywords]

def build_char_to_emoji(emoji_kw):
    """Build: single char → [emojis] mapping from keywords."""
    c2e = {}
    for emoji, keywords in emoji_kw.items():
        for kw in keywords:
            if len(kw) == 1:  # single char keyword → direct map
                c2e.setdefault(kw, []).append(emoji)
            # Also map first char of multi-char keywords
            # e.g. 微笑 → 微 gets 😊
    # Dedupe, cap at 3 emoji per char
    for c in c2e:
        c2e[c] = list(dict.fromkeys(c2e[c]))[:3]
    return c2e

def patch_cin(cin_path, out_path=None):
    emoji_kw = load_emoji_keywords()
    c2e = build_char_to_emoji(emoji_kw)

    # Also build keyword phrase → emoji for multi-char
    phrase2e = {}
    for emoji, keywords in emoji_kw.items():
        for kw in keywords:
            if len(kw) >= 2:
                phrase2e.setdefault(kw, []).append(emoji)
    for k in phrase2e:
        phrase2e[k] = list(dict.fromkeys(phrase2e[k]))[:3]

    # Parse CIN: find char → code mapping
    lines = open(cin_path, encoding='utf-8').readlines()
    
    # Find %chardef begin/end
    in_chardef = False
    char_to_codes = {}  # char → [codes]
    output_lines = []
    insert_pos = None

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == '%chardef begin':
            in_chardef = True
            output_lines.append(line)
            continue
        if stripped == '%chardef end':
            in_chardef = False
            insert_pos = len(output_lines)
            output_lines.append(line)
            continue
        
        if in_chardef and '\t' in stripped:
            parts = stripped.split('\t', 1)
            if len(parts) == 2:
                code, char = parts
                char_to_codes.setdefault(char, []).append(code)
        
        output_lines.append(line)

    # Build emoji lines to insert
    emoji_lines = []
    added = set()

    # 1. Single char: if char has emoji, add emoji under same codes
    for char, emojis in c2e.items():
        if char in char_to_codes:
            for code in char_to_codes[char]:
                for emoji in emojis:
                    key = (code, emoji)
                    if key not in added:
                        emoji_lines.append(f'{code}\t{emoji}\n')
                        added.add(key)

    # 2. Multi-char keywords: find code by looking up each char's codes
    #    e.g. 微笑 → codes for 微 + codes for 笑? No, too complex.
    #    Instead: if the keyword itself is in char_to_codes (as a phrase), use it
    for phrase, emojis in phrase2e.items():
        if phrase in char_to_codes:
            for code in char_to_codes[phrase]:
                for emoji in emojis:
                    key = (code, emoji)
                    if key not in added:
                        emoji_lines.append(f'{code}\t{emoji}\n')
                        added.add(key)

    # Insert before %chardef end
    if insert_pos is not None:
        for el in emoji_lines:
            output_lines.insert(insert_pos, el)
            insert_pos += 1

    result = ''.join(output_lines)

    if out_path:
        with open(out_path, 'w', encoding='utf-8') as f:
            f.write(result)
        print(f'✅ Patched: {len(emoji_lines)} emoji entries added')
        print(f'   {cin_path} → {out_path}')
    else:
        sys.stdout.write(result)
        print(f'# {len(emoji_lines)} emoji entries added', file=sys.stderr)

    # Show samples
    samples = {}
    for el in emoji_lines:
        code, emoji = el.strip().split('\t')
        # Find what char this code maps to
        for char, codes in char_to_codes.items():
            if code in codes and len(char) == 1:
                samples.setdefault(char, []).append((code, emoji))
                break
    
    print(f'\nSamples:', file=sys.stderr)
    shown = 0
    for char, pairs in sorted(samples.items()):
        if shown >= 10: break
        codes_emojis = ', '.join(f'{c}→{e}' for c, e in pairs[:3])
        print(f'  {char}: {codes_emojis}', file=sys.stderr)
        shown += 1

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'用法: {sys.argv[0]} input.cin [output.cin]')
        sys.exit(1)
    cin = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    patch_cin(cin, out)
