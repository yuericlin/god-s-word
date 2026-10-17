#!/usr/bin/env python3
"""Parse SWORD canon headers into a JSON versification table.
Reads include/canon.h (KJV) and include/canon_nrsv.h (NRSV vm only).
Output: versification.json with books (name, osis, chapters) and
verses_per_chapter arrays per versification.
"""
import json, re, sys

SWORD = sys.argv[1] if len(sys.argv) > 1 else \
    "/home/hatch/workspace/god-s-word/research/sword-1.9.0"

def parse_books(path):
    """Parse otbooks[]/ntbooks[] structs -> list of (name, osis, chapmax)."""
    text = open(path, encoding="utf-8", errors="replace").read()
    books = []
    for section in ("otbooks", "ntbooks"):
        m = re.search(r"struct sbook %s\[\] = \{(.*?)\};" % section, text, re.S)
        assert m, section
        for name, _abbr, osis, chapmax in re.findall(
                r'\{"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*(\d+)\}',
                m.group(1)):
            if chapmax == "0":
                continue
            books.append({"name": name, "osis": osis, "chapters": int(chapmax)})
    return books

def parse_vm(path, array_name):
    """Parse int vm[] -> dict book_name -> [verse counts per chapter]."""
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"int %s\[\] = \{(.*?)\};" % array_name, text, re.S)
    assert m, array_name
    body = m.group(1)
    books = {}
    current = None
    for line in body.splitlines():
        cm = re.search(r"//\s*(.+)", line)
        if cm:
            current = cm.group(1).strip()
            books[current] = []
        nums = re.findall(r"\d+", line.split("//")[0])
        if current is not None:
            books[current].extend(int(n) for n in nums)
    return books

def build(books, vm_by_name):
    """Assemble ordered per-chapter verse counts aligned to books list."""
    # vm dict keys are comment names like "Genesis", "I Samuel", "Song of Solomon",
    # "Psalms", "II Samuel"... map via osis id where possible.
    out_books = []
    verses = []
    # Build lookup: normalized name -> counts
    norm = {}
    for k, v in vm_by_name.items():
        norm[k.lower().replace(" ", "")] = v
        # also try without leading numeral words
    # explicit alias map for tricky ones
    for b in books:
        key = b["name"].lower().replace(" ", "")
        counts = norm.get(key)
        if counts is None:
            # try osis-based: e.g. "1Sam" -> "isamuel"?
            raise KeyError("no vm for book %r" % b["name"])
        assert len(counts) == b["chapters"], \
            "chapter count mismatch for %s: %d vs %d" % (b["name"], len(counts), b["chapters"])
        out_books.append(b)
        verses.append(counts)
    return out_books, verses

def main():
    books = parse_books(SWORD + "/include/canon.h")
    vm_kjv = parse_vm(SWORD + "/include/canon.h", "vm")
    vm_nrsv = parse_vm(SWORD + "/include/canon_nrsv.h", "vm_nrsv")
    _, kjv_verses = build(books, vm_kjv)
    _, nrsv_verses = build(books, vm_nrsv)
    data = {
        "books": books,  # 66 books, each {name, osis, chapters}
        "KJV": kjv_verses,    # [book][chapter] -> verse count
        "NRSV": nrsv_verses,
    }
    total_kjv = sum(sum(c) for c in kjv_verses)
    total_nrsv = sum(sum(c) for c in nrsv_verses)
    print("books:", len(books), "KJV verses:", total_kjv, "NRSV verses:", total_nrsv)
    json.dump(data, open("versification.json", "w"), ensure_ascii=False)
    print("wrote versification.json")

if __name__ == "__main__":
    main()
