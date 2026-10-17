#!/usr/bin/env python3
"""Full-Bible audit: every chapter's non-empty verse count must equal the
versification table's verse count. Catches systematic index-math errors."""
import sys
sys.path.insert(0, ".")
from reader import ZTextModule, BOOKS, V, testament_index

def audit(moddir, v11n):
    mod = ZTextModule(moddir, v11n)
    verses = V[v11n]
    bad = []
    total = 0
    for bi, b in enumerate(BOOKS):
        testament = 1 if bi < 39 else 2
        book1 = bi + 1 if testament == 1 else bi - 39 + 1
        for c in range(1, b["chapters"] + 1):
            expect = verses[bi][c - 1]
            got = 0
            for v in range(1, expect + 1):
                raw = mod.verse_raw(testament, book1, c, v)
                if raw:
                    got += 1
            total += got
            if got != expect:
                bad.append((b["osis"], c, expect, got))
    print(f"{v11n}: {total} verses rendered, {len(bad)} mismatched chapters")
    for b, c, e, g in bad[:20]:
        print(f"  MISMATCH {b} {c}: expected {e}, got {g}")

if __name__ == "__main__":
    audit(sys.argv[1], sys.argv[2])
