#!/usr/bin/env python3
"""Rebuild terms_*.bin: build from NAER parquet + filtered wiki entities (freq>=10, clean keys only).

1. Build NAER bins directly from naer_terms.parquet with complete domain mapping
2. Load wiki domain entities, filter by NER freq>=50 and clean key rules
3. Merge wiki entities into NAER bins and rebuild
"""
import json, re, struct, sys
from pathlib import Path
from collections import defaultdict

sys.path.insert(0, str(Path(__file__).parent))
from build_wbmm import build_wbmm, _is_clean_key

BASE = Path(__file__).resolve().parent.parent
RES = BASE / "YabomishIM" / "Resources"
WIKI_ENTITIES = BASE / "data" / "wiki_work" / "wiki_domain_entities_trad.json"
NER_PARQUET = BASE / "data" / "wiki_ner_entities.parquet"
NAER_PARQUET = BASE / "data" / "naer_terms.parquet"
FREQ_THRESHOLD = 50

DOMAIN_FILES = {
    "it": "terms_it", "ee": "terms_ee", "med": "terms_med", "law": "terms_law",
    "phy": "terms_phy", "chem": "terms_chem", "math": "terms_math",
    "biz": "terms_biz", "edu": "terms_edu", "geo": "terms_geo",
    "art": "terms_art", "mil": "terms_mil", "marine": "terms_marine",
    "material": "terms_material", "agri": "terms_agri", "media": "terms_media",
    "social": "terms_social", "govt": "terms_govt",
    "placename_intl": "terms_placename_intl",
    "power": "terms_power", "mech": "terms_mech",
    # eng split
    "eng": "terms_eng", "aero": "terms_aero", "nuclear": "terms_nuclear", "textile": "terms_textile",
    # bio split
    "bio": "terms_bio", "botany": "terms_botany", "fish": "terms_fish",
}

NAER_DOMAIN_MAP = {
    # it
    '電子計算機名詞': 'it', '圖書館學與資訊科學名詞': 'it',
    '高中以下資訊名詞': 'it', '資訊名詞-兩岸中小學教科書名詞': 'it',
    '兩岸對照名詞-計算機': 'it',
    # ee
    '電機工程名詞': 'ee', '電子工程名詞': 'ee',
    '通訊工程': 'ee', '兩岸對照名詞-通信': 'ee',
    # power
    '電力工程': 'power', '電力學名詞-兩岸電力學名詞': 'power',
    '電工學名詞-兩岸電工學名詞': 'power',
    # med
    '醫學名詞': 'med', '藥學': 'med', '病理學名詞': 'med',
    '人體解剖學': 'med', '內分泌學名詞': 'med', '獸醫學': 'med',
    '實驗動物及比較醫學名詞': 'med', '比較解剖學': 'med',
    '發生學': 'med', '新冠病毒疫情相關詞彙': 'med',
    '精神病理學': 'med', '醫學名詞-醫事檢驗名詞': 'med',
    '醫學名詞-放射醫學名詞': 'med', '細菌免疫學': 'med',
    '兩岸對照名詞-中醫': 'med', '兩岸對照名詞-醫學': 'med',
    # law
    '法律學名詞-財經法': 'law', '法律學名詞-國際法': 'law',
    '法律學名詞-性別與家事法': 'law', '法律學名詞-刑法': 'law',
    '法律學名詞-公法': 'law',
    # phy
    '物理學名詞': 'phy', '力學名詞': 'phy',
    '物理化學儀器設備名詞': 'phy', '高中以下物理學名詞': 'phy',
    '物理學名詞-聲學': 'phy', '物理學名詞-物理相關科學家': 'phy',
    '物理學名詞-兩岸中小學教科書名詞': 'phy',
    '兩岸對照名詞-物理': 'phy',
    '天文學名詞': 'phy', '計量學名詞': 'phy',
    '地球科學名詞-天文': 'phy',
    # chem
    '化學名詞-化學術語': 'chem', '化學工程名詞': 'chem',
    '化學名詞-有機化合物': 'chem', '化學名詞-兩岸化學名詞': 'chem',
    '化學名詞-無機化合物': 'chem', '高中以下化學名詞': 'chem',
    '化學名詞-兩岸中小學教科書名詞': 'chem',
    '兩岸對照名詞-化學化工': 'chem', '化學工程名詞-兩岸化學工程名詞': 'chem',
    '化學名詞-常見生物鹼及結構式': 'chem', '化學名詞-硼化合物': 'chem',
    '化學名詞-化學名詞用字之讀音': 'chem', '化學名詞-化學元素一覽表': 'chem',
    '化學名詞-常見萜類及結構式': 'chem', '化學名詞-化學相關科學家': 'chem',
    '化學名詞-不飽和雜環化合物及結構式': 'chem',
    '化學名詞-有機化合物之基': 'chem',
    # bio
    '動物學名詞': 'bio', '生命科學名詞': 'bio', '生態學名詞': 'bio',
    '高中以下生命科學名詞': 'bio', '林學': 'bio',
    '生態學名詞-兩岸生態學名詞': 'bio',
    '生命科學名詞-兩岸中小學教科書名詞': 'bio',
    '生命科學名詞-科學家譯名': 'bio',
    '兩岸對照名詞-動物 ': 'bio',
    # botany (split from bio)
    '生物學名詞-植物': 'botany', '中央研究院臺灣物種名錄': 'botany',
    '生物學名詞-植物-兩岸植物學名詞': 'botany',
    '兩岸對照名詞-植物': 'botany',
    # fish (split from bio)
    '魚類': 'fish', '兩岸對照名詞-漁業水產': 'fish',
    # math
    '數學名詞': 'math', '統計學名詞': 'math', '高中以下數學名詞': 'math',
    '數學名詞-兩岸數學名詞': 'math', '數學名詞-兩岸中小學教科書名詞': 'math',
    '兩岸對照名詞-數學': 'math',
    # biz
    '管理學名詞': 'biz', '管理學名詞-會計學': 'biz',
    '經濟學': 'biz', '市場學': 'biz', '會計學': 'biz',
    # edu
    '教育學': 'edu', '教育學名詞-科教名詞': 'edu', '設計學': 'edu',
    '教育學名詞-教社名詞': 'edu', '教育學名詞-幼教名詞': 'edu',
    '教育學名詞-特教名詞': 'edu',
    '12年國民基本教育課程綱要總綱及領綱名詞': 'edu',
    '高中以下地理學名詞': 'edu', '高中以下地球科學名詞': 'edu',
    '場所標示': 'edu', '教育部特殊專門名詞': 'edu',
    # geo
    '地質學名詞': 'geo', '海洋地質學': 'geo', '氣象學名詞': 'geo',
    '地球科學名詞-地質': 'geo', '地球科學名詞-大氣': 'geo',
    '地理學名詞-測繪學名詞': 'geo', '地理學名詞': 'geo',
    '地理學名詞-GIS名詞': 'geo', '地球科學名詞-海洋': 'geo',
    '地理學名詞-兩岸地理學名詞': 'geo',
    '地球科學名詞-太空': 'geo', '地球科學名詞': 'geo',
    '地球科學名詞-兩岸中小學教科書名詞': 'geo',
    '地球科學名詞-地球物理': 'geo', '地球科學名詞-水文': 'geo',
    '地理學名詞-兩岸中小學教科書名詞': 'geo',
    '兩岸對照名詞-地質': 'geo', '兩岸對照名詞-大氣科學': 'geo',
    '兩岸對照名詞-測繪學': 'geo', '兩岸對照名詞-地理': 'geo',
    '兩岸對照名詞-海洋': 'geo', '兩岸對照名詞-環境保護': 'geo',
    '土壤學名詞': 'geo', '測量學': 'geo',
    # placename_intl
    '外國地名譯名': 'placename_intl',
    # eng
    '土木工程名詞': 'eng', '工業工程名詞': 'eng', '工程圖學': 'eng',
    '水利工程': 'eng', '生產自動化': 'eng', '交通': 'eng',
    # aero (split from eng)
    '航空太空名詞': 'aero', '兩岸對照名詞-航天': 'aero', '兩岸對照名詞-航空': 'aero',
    # nuclear (split from eng)
    '核能名詞': 'nuclear',
    # textile (split from eng)
    '食品科技': 'textile', '紡織科技': 'textile',
    '兩岸對照名詞-紡織': 'textile', '兩岸對照名詞-輕工': 'textile',
    # mech
    '機械工程名詞': 'mech', '機械名詞-兩岸機械名詞': 'mech',
    '兩岸對照名詞-機械': 'mech', '機構與機器原理': 'mech',
    # art
    '視覺藝術名詞': 'art', '漢語文化特色詞條': 'art',
    '音樂名詞': 'art', '舞蹈名詞': 'art',
    '音樂名詞-音樂家': 'art', '音樂名詞-兩岸音樂名詞': 'art',
    '音樂名詞-兩岸音樂人名': 'art', '音樂名詞-樂器名': 'art',
    '音樂名詞-流行音樂專有名詞音響類': 'art',
    '音樂名詞-音樂歌劇譯名': 'art', '音樂名詞-流行音樂樂團名': 'art',
    '音樂名詞-兩岸音樂作品名詞': 'art',
    # mil
    '國防部新編國軍簡明美華軍語辭典': 'mil',
    # marine
    '海事': 'marine', '海洋科技名詞-造船工程': 'marine',
    '海洋科學名詞-兩岸造船工程': 'marine', '海洋科學名詞-兩岸海洋科學名詞': 'marine',
    '海洋科學名詞': 'marine', '海洋科技名詞-水下工程': 'marine',
    '海洋科學名詞-近岸工程': 'marine', '海洋科學名詞-離岸工程': 'marine',
    '造船工程名詞': 'marine',
    # material
    '礦物學名詞': 'material', '材料科學名詞': 'material',
    '材料科學名詞-兩岸材料科學名詞': 'material', '礦冶工程名詞': 'material',
    '鑄造學': 'material',
    # agri
    '農業機械名詞': 'agri', '農業推廣學': 'agri',
    '兩岸對照名詞-農業': 'agri', '兩岸對照名詞-林學': 'agri',
    '兩岸對照名詞-畜牧': 'agri',
    '畜牧學': 'agri', '肥料學': 'agri',
    # media
    '新聞傳播學名詞': 'media',
    '出版、社群媒體、科技及關稅詞彙': 'media',
    # social
    '社會工作與福利名詞': 'social', '行政學名詞': 'social',
    '選舉詞彙': 'social',
    '社會學名詞': 'social', '心理學名詞': 'social',
    '心理學名詞-兩岸心理學名詞': 'social',
    # govt
    '中央機關單位名稱': 'govt', '中央機關一般職稱': 'govt',
    '中央機關銜稱': 'govt', '中央機關主管職稱': 'govt',
    '中央機關首長職稱': 'govt', '地方機關單位名稱': 'govt',
    '地方機關一般職稱': 'govt', '地方機關銜稱': 'govt',
    '地方機關首長職稱': 'govt', '地方機關主管職稱': 'govt',
    '中小學常用職稱及場所、單位名稱': 'govt',
    '國家教育研究院場所名詞': 'govt', '科技部政務次長及常務次長英譯': 'govt',
    '考選部雙語詞彙': 'govt',
    '業務標示': 'govt', '其他': 'govt',
    '東南亞6國詞彙': 'govt',
}


def load_ner_freq():
    """Load NER entity frequencies from parquet."""
    import pandas as pd
    df = pd.read_parquet(NER_PARQUET)
    return dict(zip(df["entity"], df["freq"]))


def load_naer_terms(binpath):
    """Read existing WBMM bin and extract {key: [vals]}."""
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


_BRACKET_RE = re.compile(r'[{｛〔\[（【].+?[}｝〕\]）】]')
_STRAY_BRACKET_RE = re.compile(r'[{｛}｝〔〕\[\]（）【】]')
_ENGLISH_RE = re.compile(r'[a-zA-Z]{3,}')

def _clean_naer_terms(raw_terms):
    """Split on ；/;/，/,  strip brackets/annotations, drop English and overlong terms."""
    out = set()
    for t in raw_terms:
        parts = re.split(r'[；;，,]', t)
        for p in parts:
            p = _BRACKET_RE.sub('', p)
            p = _STRAY_BRACKET_RE.sub('', p).strip()
            p = re.sub(r'\s+', '', p)  # collapse spaces
            if not p or len(p) < 2 or len(p) > 8:
                continue
            if _ENGLISH_RE.search(p):
                continue
            out.add(p)
    return list(out)


def build_naer_from_parquet():
    """Build NAER bins directly from naer_terms.parquet using NAER_DOMAIN_MAP."""
    import pandas as pd
    df = pd.read_parquet(NAER_PARQUET)
    total = len(df)

    # Report unmapped domains
    mapped_mask = df["domain"].isin(NAER_DOMAIN_MAP)
    unmapped = df.loc[~mapped_mask]
    unmapped_domains = unmapped["domain"].value_counts()
    print(f"  Unmapped: {len(unmapped):,} rows ({len(unmapped)/total*100:.1f}%) "
          f"across {len(unmapped_domains)} domain categories:")
    for dom, cnt in unmapped_domains.items():
        print(f"    {dom}: {cnt:,}")

    # Group mapped terms by bin domain
    mapped = df.loc[mapped_mask].copy()
    mapped["bin"] = mapped["domain"].map(NAER_DOMAIN_MAP)
    total_mapped = 0

    for bin_domain, fname in DOMAIN_FILES.items():
        raw_terms = mapped.loc[mapped["bin"] == bin_domain, "zh"].dropna().unique()
        terms = _clean_naer_terms(raw_terms)
        entries = defaultdict(list)
        for term in terms:
            for plen in range(2, len(term)):
                prefix = term[:plen]
                suffix = term[plen:]
                if suffix and len(entries[prefix]) < 8:
                    entries[prefix].append(suffix)
        binpath = RES / f"{fname}.bin"
        build_wbmm(dict(entries), str(binpath))
        total_mapped += len(terms)
        print(f"  {fname}: {len(raw_terms):,} raw → {len(terms):,} clean → {len(entries):,} keys")

    print(f"  Total mapped: {total_mapped:,} unique terms from {len(mapped):,} rows")


def main():
    print("Step 1: Build NAER bins from parquet")
    build_naer_from_parquet()

    print("\nStep 2: Load wiki entities + NER freq")
    with open(WIKI_ENTITIES) as f:
        wiki_domains = json.load(f)
    ner_freq = load_ner_freq()
    print(f"  NER freq table: {len(ner_freq):,} entities")

    print(f"\nStep 3: Filter wiki entities (freq >= {FREQ_THRESHOLD}, clean keys)")
    for domain, entities in wiki_domains.items():
        before = len(entities)
        filtered = [e for e in entities
                    if _is_clean_key(e) and 3 <= len(e) <= 8 and ner_freq.get(e, 0) >= FREQ_THRESHOLD]
        wiki_domains[domain] = filtered
        print(f"  {domain}: {before:,} → {len(filtered):,}")

    print("\nStep 4: Merge wiki entities and rebuild all bins")
    for domain, fname in DOMAIN_FILES.items():
        binpath = RES / f"{fname}.bin"
        naer = load_naer_terms(binpath)
        wiki_entities = wiki_domains.get(domain, [])

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
