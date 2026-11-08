#!/usr/bin/env python3
"""Harvest PC GH3.exe addresses + names from GH3+ / BetterGH3 / gh3ml sources.

Reads (never executes) the reference trees under ref/:
  BetterGH3/GH3Plus/   (vendored GH3+, donnaken15 lineage)
  GH3-Plus/            (ExileLord upstream)
  GH3-Plus-donnaken15/ (fork with Logger/AssertPoints.h, extra GH3Functions.h)
  gh3ml/               (Bambo-Borris mod loader)
and the Cheat Engine tables (gh3.CT). Emits:

  docs/data/gh3plus_symbols.tsv : va<TAB>kind<TAB>name<TAB>source
    kind  = func   (address is a plausible function entry in .text/HATRED)
          | global (address lies in .rdata/.data/.bss)
    source= comma-joined repo-relative files that gave this (va, name)

Patterns recognised:
  #define ADDR_<name> 0x...              (GH3GlobalAddresses.h)
  T * Name = (T *)(0x...);               (GH3Functions.h)
  ... Name = reinterpret_cast<...>(0x...)  / (T*)0x... / *(T*)0x...
  NativeInsertCall<0x..., T>             -> QbStruct::Insert_<T>
  static const void *function = (void*)0x...   -> enclosing Class::Method
  Binding<0x..., ...> / Orig<0x..., ...> with 'using Name =' or enclosing fn
  EXTN_FUNC(ret, Name, 0x...)
  AIF(start, end, "Name")                (Logger/AssertPoints.h, IDA export)
  CT: <CheatEntry> Description + Address (absolute or gh3.exe+off; pointer
      bases flagged "(ptr base)"), <UserdefinedSymbols>.

Addresses in code that are not plausible function entries (mid-function
detour/return/patch sites) are dropped and only counted; names that look like
sites (detour/return/ret/jz/addr/...) are dropped for code addresses.
Function-entry test: target of an E8 rel32 call, or of a CFunc table entry,
or 16-byte aligned with a preceding 0xCC/0xC3/0x90 byte, or an AIF start.

Usage: python3 -I tools/extract_gh3plus_symbols.py [GH3.exe] [ref_dir] [out.tsv]
Stdlib only.
"""
import os
import re
import struct
import sys
from collections import defaultdict

HEX = r"0x0*([0-9A-Fa-f]{6,8})"
SITE_WORDS = re.compile(r"(?i)(detour|return|retaddr|^ret|jz|jnz|jmp|addr\d|site|takeover|patch|reference|_nearby|start$|^ADDROP)")


class PE:
    def __init__(self, data):
        self.d = data
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        nsec = struct.unpack_from("<H", data, pe + 6)[0]
        optsz = struct.unpack_from("<H", data, pe + 20)[0]
        opt = pe + 24
        self.base = struct.unpack_from("<I", data, opt + 28)[0]
        self.image_end = self.base + struct.unpack_from("<I", data, opt + 56)[0]
        self.secs = []
        for i in range(nsec):
            o = opt + optsz + 40 * i
            name = data[o:o + 8].rstrip(b"\0").decode("latin1")
            vsize, va, rsize, raw = struct.unpack_from("<IIII", data, o + 8)
            chars = struct.unpack_from("<I", data, o + 36)[0]
            self.secs.append((name, self.base + va, vsize, raw, rsize, chars))

    def sec(self, va):
        for s in self.secs:
            if s[1] <= va < s[1] + max(s[2], s[4]):
                return s
        return None

    def is_code(self, va):
        s = self.sec(va)
        return bool(s and s[5] & 0x20000000)

    def byte(self, va):
        s = self.sec(va)
        if not s or va - s[1] >= s[4]:
            return None
        return self.d[s[3] + va - s[1]]

    def call_targets(self):
        tg = set()
        for name, va, vsize, raw, rsize, chars in self.secs:
            if not chars & 0x20000000:
                continue
            blob = self.d[raw:raw + rsize]
            i = blob.find(b"\xE8")
            while i >= 0 and i + 5 <= len(blob):
                t = (va + i + 5 + struct.unpack_from("<i", blob, i + 1)[0]) & 0xFFFFFFFF
                tg.add(t)
                i = blob.find(b"\xE8", i + 1)
        return tg

    def cfunc_targets(self):
        """Function pointers of the {name, fn} script table (see extract_cfuncs.py)."""
        out = set()
        for name, va, vsize, raw, rsize, chars in self.secs:
            if chars & 0x20000000:
                continue
            for o in range(raw, raw + rsize - 8, 4):
                p, f = struct.unpack_from("<II", self.d, o)
                if self.is_code(f) and (s := self.sec(p)) and not s[5] & 0x20000000:
                    out.add(f)
        return out


def enclosing_fn(lines, idx):
    pat = re.compile(r"([A-Za-z_][\w:]*::[A-Za-z_~]\w*|\b[A-Za-z_]\w*)\s*\([^;{}]*\)\s*(const)?\s*\{?\s*$")
    for j in range(idx, max(-1, idx - 30), -1):
        m = pat.search(lines[j].strip())
        if m and not re.match(r"(if|for|while|switch|return|sizeof)\b", m.group(1)):
            return m.group(1)
    return None


def parse_source(path, rel, emit):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    lines = text.splitlines()
    for i, raw in enumerate(lines):
        line = raw.split("//")[0]
        if "0x" not in line:
            continue
        m = re.search(r"#define\s+ADDR_(\w+)\s+" + HEX, line)
        if m:
            emit(int(m.group(2), 16), m.group(1), rel, "define")
            continue
        m = re.search(r"AIF\(\s*" + HEX + r"\s*,\s*" + HEX + r'\s*,\s*"([^"]+)"', line)
        if m:
            emit(int(m.group(1), 16), m.group(3), rel, "aif")
            continue
        m = re.search(r"EXTN_FUNC\(\s*[^,]+,\s*(\w+)\s*,\s*" + HEX, line)
        if m:
            emit(int(m.group(2), 16), m.group(1), rel, "assign")
            continue
        m = re.search(r"NativeInsertCall<\s*" + HEX + r"\s*,\s*([\w\s\*]+?)\s*>", line)
        if m:
            t = re.sub(r"\W+", "", m.group(2).replace("*", "Ptr"))
            emit(int(m.group(1), 16), "QbStruct::Insert_" + t, rel, "assign")
            continue
        m = re.search(r"using\s+(\w+)\s*=\s*[\w:]*Binding<\s*" + HEX, line)
        if m:
            emit(int(m.group(2), 16), m.group(1), rel, "assign")
            continue
        m = re.search(r"(?:Orig|Binding|CreateHook)<\s*" + HEX, line)
        if m:
            fn = enclosing_fn(lines, i)
            if fn:
                emit(int(m.group(1), 16), fn, rel, "assign")
            continue
        # Name = cast(0x...)  /  T &Name = *(T*)0x...
        m = re.search(r"(\w+)\s*(?:\)\s*\([^)]*\))?\s*=\s*\*?\s*(?:reinterpret_cast<[^>]*>|\([^()]*\))?\s*\(?\s*" + HEX + r"\s*\)?\s*[;,)]", line)
        if m:
            name = m.group(1)
            if name in ("function", "nativeFunction"):
                fn = enclosing_fn(lines, i - 1)
                if not fn:
                    continue
                name = fn
            emit(int(m.group(2), 16), name, rel, "assign")


def parse_ct(path, rel, emit, base):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    for m in re.finditer(r"<CheatEntry>(.*?)</CheatEntry>", text, re.S):
        body = m.group(1)
        if "<CheatEntry>" in body:  # group header with children: take own fields only
            body = body.split("<CheatEntries>")[0]
        d = re.search(r"<Description>\"?(.*?)\"?</Description>", body)
        a = re.search(r"<Address>(.*?)</Address>", body)
        if not d or not a:
            continue
        addr = a.group(1).strip()
        mm = re.fullmatch(r"(?i)gh3\.exe\+([0-9a-f]+)", addr)
        if mm:
            va = base + int(mm.group(1), 16)
        elif re.fullmatch(r"(?i)(0x)?[0-9a-f]{5,8}", addr):
            va = int(addr, 16)
        else:
            continue  # other module (game.exe+..) or symbolic
        name = d.group(1)
        if "<Offsets>" in body:
            name += " (ptr base)"
        emit(va, name, rel, "ct")
    for m in re.finditer(r"<SymbolEntry>\s*<Name>(.*?)</Name>\s*<Address>(.*?)</Address>", text, re.S):
        if re.fullmatch(r"(?i)(0x)?[0-9a-f]{5,8}", m.group(2).strip()):
            emit(int(m.group(2), 16), m.group(1), rel, "ct")


def clean(name):
    name = name.strip().replace("\t", " ")
    if name.startswith("?"):  # MSVC mangled: keep verbatim
        return name
    name = re.sub(r"[^\w:]+", "_", name).strip("_")
    return name or None


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "work", "GH3.exe")
    ref = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "ref")
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(root, "docs", "data", "gh3plus_symbols.tsv")
    with open(exe, "rb") as fh:
        pe = PE(fh.read())
    calls = pe.call_targets()
    cfuncs = pe.cfunc_targets()

    raw = []  # (va, name, rel, how)

    def emit(va, name, rel, how):
        raw.append((va, name, rel, how))

    trees = ["BetterGH3/GH3Plus", "GH3-Plus", "GH3-Plus-donnaken15", "gh3ml"]
    for t in trees:
        top = os.path.join(ref, t)
        for dp, dn, fn in os.walk(top):
            dn[:] = [d for d in dn if d != ".git"]
            for f in sorted(fn):
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, ref)
                if f.endswith(".CT"):
                    parse_ct(p, rel, emit, pe.base)
                elif f.endswith((".h", ".hpp", ".cpp", ".c", ".inl")) and not re.search(r"Keys\.h(pp)?$", f):
                    parse_source(p, rel, emit)

    rows = defaultdict(set)
    dropped_site = dropped_range = 0
    for va, name, rel, how in raw:
        name = clean(name) if name else None
        if not name:
            continue
        if not (pe.base <= va < pe.image_end) or pe.sec(va) is None:
            dropped_range += 1
            continue
        if pe.is_code(va):
            entry = (va in calls or va in cfuncs or how == "aif"
                     or (va % 16 == 0 and pe.byte(va - 1) in (0xCC, 0xC3, 0x90)))
            if entry and re.search(r"(?i)_?detour$", name) and len(name) > 8:
                # "FooDetour" hooked at a function entry names the function itself
                name = re.sub(r"(?i)_?detour$", "", name)
            if not entry or SITE_WORDS.search(name):
                dropped_site += 1
                continue
            kind = "func"
        else:
            kind = "global"
        rows[(va, kind, name)].add(rel)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        for (va, kind, name), srcs in sorted(rows.items()):
            fh.write(f"0x{va:08x}\t{kind}\t{name}\t{','.join(sorted(srcs))}\n")
    vas = {(va, kind) for va, kind, _ in rows}
    nf = sum(1 for _, k in vas if k == "func")
    print(f"{out}: {len(rows)} rows; {len(vas)} distinct addresses ({nf} func, {len(vas) - nf} global); "
          f"dropped {dropped_site} code sites, {dropped_range} out-of-image", file=sys.stderr)


if __name__ == "__main__":
    main()
