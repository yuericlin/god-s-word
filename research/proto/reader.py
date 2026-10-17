#!/usr/bin/env python3
"""Prototype SWORD zText reader: parse module files, render a chapter.
Validates: index math, zlib blocks, OSIS stripping.
"""
import json, re, struct, sys, zlib, zipfile, html, io

V = json.load(open("versification.json"))
BOOKS = V["books"]  # [{name, osis, chapters}] in canonical order

def build_offsets(v11n):
    """Return (chapter_offsets, nt_start) mirroring SWORD loadFromSBook/getOffsetFromVerse.

    chapter_offsets[(testament, book1, chapter)] = absolute offset of chapter HEADING.
    testamentIndex(book1, chapter, verse) = chapter_heading_offset + verse
        - (nt_start if testament == 2 else 0)
    """
    verses = V[v11n]
    chapter_offsets = {}
    offset = 0          # module heading
    offset += 1         # OT testament heading -> 1
    for bi in range(39):  # OT books 1..39
        b = BOOKS[bi]
        offset += 1     # book heading
        for c in range(1, b["chapters"] + 1):
            offset += 1  # chapter heading
            chapter_offsets[(1, bi + 1, c)] = offset
            offset += verses[bi][c - 1]
    nt_start = offset
    offset += 1         # NT testament heading
    for bi in range(39, 66):  # NT books 1..27
        b = BOOKS[bi]
        offset += 1
        for c in range(1, b["chapters"] + 1):
            offset += 1
            chapter_offsets[(2, bi - 39 + 1, c)] = offset
            offset += verses[bi][c - 1]
    return chapter_offsets, nt_start

def testament_index(v11n, testament, book1, chapter, verse):
    offs, nt_start = OFFSETS[v11n]
    idx = offs[(testament, book1, chapter)] + verse
    if testament == 2:
        idx -= nt_start
    return idx

OFFSETS = {"KJV": build_offsets("KJV"), "NRSV": build_offsets("NRSV")}

TAG_RE = re.compile(r"<[^>]*>")
NOTE_RE = re.compile(r"<note\b.*?</note\s*>", re.S | re.I)
WS_RE = re.compile(r"\s+")

def osis_to_text(osis):
    t = NOTE_RE.sub("", osis)          # drop footnotes / crossrefs
    t = re.sub(r"<lb\b[^>]*/>", " ", t, flags=re.I)
    t = re.sub(r"<milestone\b[^>]*/>", "", t, flags=re.I)
    t = TAG_RE.sub("", t)              # strip remaining tags, keep inner text
    t = html.unescape(t)
    t = t.replace("\u00a0", " ")
    t = WS_RE.sub(" ", t).strip()
    return t

class ZTextModule:
    def __init__(self, moddir, v11n):
        self.v11n = v11n
        self.idx = {}   # testament -> list of (buffnum, start, size)
        self.blocks = {}  # testament -> list of (compOff, compSize, uncompSize)
        self.data = {}
        self.cache = {}
        for ti, tag in ((1, "ot"), (2, "nt")):
            try:
                with open(f"{moddir}/{tag}.bzv", "rb") as f:
                    raw = f.read()
                n = len(raw) // 10
                self.idx[ti] = [struct.unpack_from("<IIH", raw, i * 10) for i in range(n)]
                with open(f"{moddir}/{tag}.bzs", "rb") as f:
                    raw = f.read()
                n = len(raw) // 12
                self.blocks[ti] = [struct.unpack_from("<III", raw, i * 12) for i in range(n)]
                with open(f"{moddir}/{tag}.bzz", "rb") as f:
                    self.data[ti] = f.read()
            except FileNotFoundError:
                self.idx[ti] = []
        print(f"  OT verses indexed: {len(self.idx[1])}, NT: {len(self.idx[2])}, "
              f"OT blocks: {len(self.blocks[1])}, NT blocks: {len(self.blocks[2])}")

    def verse_raw(self, testament, book1, chapter, verse):
        ti = testament_index(self.v11n, testament, book1, chapter, verse)
        entries = self.idx[testament]
        if ti < 0 or ti >= len(entries):
            return None
        buffnum, start, size = entries[ti]
        if size == 0:
            return None
        key = (testament, buffnum)
        if key not in self.cache:
            comp_off, comp_size, _uncomp = self.blocks[testament][buffnum]
            comp = self.data[testament][comp_off:comp_off + comp_size]
            self.cache[key] = zlib.decompress(comp)
        return self.cache[key][start:start + size].decode("utf-8", errors="replace")

    def chapter(self, testament, book1, chapter):
        verses = V[self.v11n][(book1 - 1) if testament == 1 else (39 + book1 - 1)]
        out = []
        for v in range(1, verses[chapter - 1] + 1):
            raw = self.verse_raw(testament, book1, chapter, v)
            out.append((v, osis_to_text(raw) if raw else None))
        return out

def book_num(osis):
    for i, b in enumerate(BOOKS):
        if b["osis"].lower() == osis.lower():
            return i  # 0-based overall
    raise KeyError(osis)

def main():
    moddir, v11n, t_osis, chap = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    bi = book_num(t_osis)
    testament = 1 if bi < 39 else 2
    book1 = bi + 1 if testament == 1 else bi - 39 + 1
    mod = ZTextModule(moddir, v11n)
    for v, text in mod.chapter(testament, book1, chap):
        print(f"{v} {text}")

if __name__ == "__main__":
    main()
