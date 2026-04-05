#!/usr/bin/env python3
"""
Yabomish IME 三層排序原型 — 互動測試

用法: python3 tools/ime_prototype.py
  輸入注音（空白分隔聲母韻母聲調），例如:
    ㄇㄠˊ ㄗㄜˊ ㄉㄨㄥ    → 毛澤東
    ㄊㄞˊ ㄨㄢ           → 臺灣
    ㄌㄧㄤˊ ㄗˇ          → 量子

  指令:
    :ctx          顯示當前 session 社群上下文
    :reset        重置 session
    :q            離開
"""
import sqlite3, sys
from collections import Counter
from pathlib import Path

DB = Path(__file__).resolve().parent.parent / "data" / "yabomish_ime.db"


class IMEEngine:
    def __init__(self, db_path):
        self.conn = sqlite3.connect(str(db_path))
        self.conn.execute("PRAGMA cache_size=-8000")  # 8MB cache
        self.session_communities = Counter()  # community_id → count
        self.prev_char = None
        self.committed = []  # history of committed text

    def lookup_chars(self, zhuyin, prev_char=None):
        """Layer 1+2: zhuyin → chars, with bigram boost."""
        # Base candidates
        rows = self.conn.execute(
            "SELECT char, freq FROM zhuyin_base WHERE zhuyin=? ORDER BY freq DESC",
            (zhuyin,)).fetchall()
        if not rows:
            return []

        # Bigram boost
        if prev_char:
            prev_zys = self.conn.execute(
                "SELECT DISTINCT zhuyin FROM zhuyin_base WHERE char=?",
                (prev_char,)).fetchall()
            boost = {}
            for (pzy,) in prev_zys:
                for ch, freq in self.conn.execute(
                    "SELECT char, freq FROM bigram WHERE prev_zy=? AND cur_zy=?",
                    (pzy, zhuyin)):
                    boost[ch] = max(boost.get(ch, 0), freq)
            if boost:
                boosted = [(ch, f) for ch, f in boost.items()]
                boosted.sort(key=lambda x: x[1], reverse=True)
                boost_set = set(b[0] for b in boosted)
                rest = [(ch, f) for ch, f in rows if ch not in boost_set]
                return boosted + rest

        return rows

    @staticmethod
    def _zy_hash(zhuyin_key):
        import hashlib, struct
        return struct.unpack('<q', hashlib.sha1(zhuyin_key.encode()).digest()[:8])[0]

    def lookup_phrases(self, zhuyin_seq):
        """Layer 2: zhuyin sequence → NER phrases."""
        h = self._zy_hash("".join(zhuyin_seq))
        rows = self.conn.execute(
            "SELECT phrase, freq, community FROM ner_phrase WHERE zy_hash=? ORDER BY freq DESC LIMIT 20",
            (h,)).fetchall()
        return rows

    def lookup_prefix_phrases(self, zhuyin_seq):
        """Prefix match via zy_hash_map."""
        key = "".join(zhuyin_seq)
        # Get all zhuyin_keys starting with this prefix, then hash-lookup
        rows = self.conn.execute(
            "SELECT zy_hash FROM zy_hash_map WHERE zhuyin_key LIKE ? LIMIT 50",
            (key + "%",)).fetchall()
        if not rows:
            return []
        exact_h = self._zy_hash(key)
        hashes = [r[0] for r in rows if r[0] != exact_h]
        if not hashes:
            return []
        placeholders = ",".join("?" * len(hashes))
        return self.conn.execute(
            f"SELECT phrase, freq, community FROM ner_phrase WHERE zy_hash IN ({placeholders}) ORDER BY freq DESC LIMIT 10",
            hashes).fetchall()

    def community_boost(self, candidates_with_comm):
        """Layer 3: boost candidates matching active session communities."""
        if not self.session_communities:
            return candidates_with_comm
        total = sum(self.session_communities.values())
        boosted = []
        for item in candidates_with_comm:
            comm = item[-1]  # last element is community
            if comm >= 0 and comm in self.session_communities:
                score = self.session_communities[comm] / total
                boosted.append((*item, score))
            else:
                boosted.append((*item, 0.0))
        boosted.sort(key=lambda x: (-x[-1], -x[2]))  # sort by comm_boost desc, then freq desc
        return boosted

    def commit(self, text):
        """User committed text — update session context."""
        self.committed.append(text)
        self.prev_char = text[-1] if text else None
        # Update community context
        for ch in text:
            rows = self.conn.execute(
                "SELECT community FROM community WHERE entity=?", (ch,)).fetchall()
            for (c,) in rows:
                self.session_communities[c] += 1
        # Also check full text as entity
        rows = self.conn.execute(
            "SELECT community FROM community WHERE entity=?", (text,)).fetchall()
        for (c,) in rows:
            self.session_communities[c] += 3  # stronger signal for exact entity match

    def show_context(self):
        top = self.session_communities.most_common(10)
        if not top:
            print("  (空)")
            return
        for comm_id, count in top:
            label = self.conn.execute(
                "SELECT entity FROM community WHERE community=? LIMIT 1",
                (comm_id,)).fetchone()
            lbl = label[0] if label else "?"
            print(f"  comm {comm_id:3d} ({lbl:15s}): {count}")


def main():
    engine = IMEEngine(DB)
    print("Yabomish IME 原型 (三層排序)")
    print("輸入注音（空白分隔），例如: ㄇㄠˊ ㄗㄜˊ ㄉㄨㄥ")
    print(":ctx = 顯示社群上下文, :reset = 重置, :q = 離開\n")

    while True:
        try:
            line = input("注音> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        if line == ":q":
            break
        if line == ":ctx":
            engine.show_context()
            continue
        if line == ":reset":
            engine.session_communities.clear()
            engine.prev_char = None
            engine.committed.clear()
            print("  已重置")
            continue

        zhuyins = line.split()

        # ── Phrase match (exact) ──
        phrases = engine.lookup_phrases(zhuyins)
        if phrases:
            print(f"  【詞組】")
            for phrase, freq, comm in phrases[:10]:
                comm_mark = "★" if comm >= 0 and comm in engine.session_communities else " "
                print(f"    {comm_mark} {phrase:15s} freq={freq:,}")

        # ── Prefix phrase match ──
        if len(zhuyins) >= 2:
            prefix = engine.lookup_prefix_phrases(zhuyins)
            prefix = [p for p in prefix if p[0] not in {r[0] for r in phrases}]
            if prefix:
                print(f"  【延伸詞組】")
                for phrase, freq, comm in prefix[:5]:
                    print(f"    {phrase:15s} freq={freq:,}")

        # ── Char-by-char (last zhuyin) ──
        last_zy = zhuyins[-1]
        chars = engine.lookup_chars(last_zy, prev_char=engine.prev_char)
        if chars:
            top10 = [ch for ch, _ in chars[:10]]
            print(f"  【單字】{' '.join(top10)}")

        # ── Auto-commit first phrase or ask ──
        if phrases:
            choice = phrases[0][0]
            print(f"  → 自動選: {choice}")
            engine.commit(choice)
        elif chars:
            choice = chars[0][0]
            engine.commit(choice)

    print("bye")


if __name__ == "__main__":
    main()
