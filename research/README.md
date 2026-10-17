# Research notes — SWORD module format (for the clean-room Swift reader)

These notes document how `SwordReader/` understands CrossWire SWORD modules.
Derived from reading the SWORD 1.9.0 sources (GPLv2 — none of its code is
used; this is a clean-room reimplementation) and verified against real
downloaded modules.

## Module packages

- Repository root (CrossWire main): `https://crosswire.org/ftpmirror/pub/sword/raw`
- Catalog: `{root}/mods.d.tar.gz` (gzipped tar, one `.conf` per module, 428 files)
- Module zip: `{root}/packages/<ModuleID>.zip` (e.g. `KJV.zip`, `ChiUns.zip`)
- Zip contents: `mods.d/<id>.conf` + `modules/texts/ztext/<dir>/ot.bzv` etc.

## zText layout (BlockType=BOOK, CompressType=ZIP)

Per testament (`ot` / `nt`), three files (`zverse.cpp`):

| file | entry | size | fields (little-endian) |
|---|---|---|---|
| `.bzv` | verse index | 10 B | u32 block#, u32 start, u16 size |
| `.bzs` | block index | 12 B | u32 compOffset, u32 compSize, u32 uncompSize |
| `.bzz` | data | — | concatenated zlib-wrapped deflate blocks |

Entry `i` of `.bzv` lives at byte offset `i*10`; block `b` of `.bzs` at `b*12`.
Verse text = `inflate(.bzz[compOffset ..< compOffset+compSize])[start ..< start+size]`.
Empty verse (size 0) = no text (mirrors `zText::hasEntry`). All integers are
little-endian (`sysdata.h`: identity swap when `!WORDS_BIGENDIAN`).

Compression is zlib-wrapped deflate (RFC 1950): `ZipCompress::decode` uses
zlib `uncompress()`, and `encode` uses `compress2()`.

## Verse index math (mirrors `VersificationMgr::System` + `VerseKey`)

From `loadFromSBook` (`versificationmgr.cpp`):

```
offset = 0            # module heading
offset += 1           # OT testament heading
for each OT book: offset += 1            # book heading
  for each chapter: offset += 1          # chapter heading  <- offsetPrecomputed
                    offset += verseMax
ntStart = offset
offset += 1           # NT testament heading
... same for NT ...
testamentIndex = offsetPrecomputed[chapter] + verse - (ntStart if NT else 0)
```

So Gen 1:1 → index 4, Matt 1:1 → index 4 (within NT). Verified: full-Bible
audit renders all 31,102 KJV verses with zero chapter mismatches.

## Versification tables

- `include/canon.h` = KJV system (otbooks/ntbooks + `vm[]` verse counts)
- `include/canon_nrsv.h` = NRSV system (same book order, `vm_nrsv[]`)
- `VersificationData.swift` is generated from these by `proto/parse_canon.py`.

## App filter (what v1 renders)

`ModDrv=zText`, `CompressType=ZIP`, `BlockType=BOOK`, `SourceType=OSIS`,
`Encoding=UTF-8`, no `CipherKey`, `Versification` in {KJV, NRSV}.
That covers 109+ modules incl. KJV, ChiUns (和合本简体), ChiUn (繁體).

## Verification

- `proto/reader.py` + `proto/audit.py`: Python prototype, full-Bible audits
  (KJV 31,102/31,102; ChiUns 31,103 rendered — John 7:53 is genuinely empty
  in the module, confirmed against bolls.life's CUVS too).
- `SwordReader` Swift package: 17 unit tests + a fixture test that unzips
  real `KJV.zip`/`ChiUns.zip`, audits all verses, parses the real catalog,
  and spot-checks text (runs with `FIXTURE_DIR=…`; not committed to CI).
- Oracle for spot checks: https://bolls.life (same CrossWire module family).

## Files here

- `proto/` — format-exploration scripts (canon parser, reader, audit)
- `sword-1.9.0/` — SWORD sources (reference only, git-ignored)
- `modules/` — downloaded module zips (git-ignored)
- `catalog/mods.d/` — extracted catalog (git-ignored)
