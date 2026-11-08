#!/usr/bin/env python3
"""Extract the QB script C-function registration table from GH3.exe (PC, Aspyr 2007).

GH3 registers native script functions through a static array of
    struct { const char *name; bool (*fn)(Script::CStruct*, Script::CScript*); }
in .data, passed with its element count to the script registrar at startup:

    0x41756d  call 0x4134a0        ; mov eax, 0x492 ; ret   (count = 1170)
    0x417572  push eax
    0x417573  push 0x9551b8        ; table
    0x417578  call 0x4a6a70        ; register C functions
    0x417580  call 0x4134b0        ; mov eax, 0x5a ; ret    (count = 90)
    0x417585  push eax
    0x417586  push 0x957648        ; member-function name list (char*[])
    0x41758b  call 0x4a6ac0        ; register member-function names

The script finds the table heuristically (longest run of {ptr->identifier
string, ptr->code} pairs in .data/.rdata) and then confirms the element count
from the `push eax; push <table>` call site and its `mov eax, imm32; ret`
count getter. Nothing is hard-coded except the PE file path defaults.

Usage:
    python3 -I scripts/dev/extract_cfuncs.py [GH3.exe] [out_dir]
Outputs (out_dir defaults to docs/data next to this repo's tools/):
    cfuncs.tsv          va<TAB>name   (one row per table entry, table order;
                                       aliased functions appear once per name)
    cmemberfuncs.tsv    str_va<TAB>name (member-function names, no code ptr)
Stdlib only. Read-only on the input.
"""
import os
import re
import struct
import sys

IDENT = re.compile(rb"^[A-Za-z_][A-Za-z0-9_]{1,95}$")


class PE:
    def __init__(self, data):
        self.d = data
        if data[:2] != b"MZ":
            raise SystemExit("not an MZ file")
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe:pe + 4] != b"PE\0\0":
            raise SystemExit("not a PE file")
        nsec = struct.unpack_from("<H", data, pe + 6)[0]
        optsz = struct.unpack_from("<H", data, pe + 20)[0]
        opt = pe + 24
        self.base = struct.unpack_from("<I", data, opt + 28)[0]
        self.secs = []
        sh = opt + optsz
        for i in range(nsec):
            o = sh + 40 * i
            name = data[o:o + 8].rstrip(b"\0").decode("latin1")
            vsize, va, rsize, raw = struct.unpack_from("<IIII", data, o + 8)
            chars = struct.unpack_from("<I", data, o + 36)[0]
            self.secs.append((name, self.base + va, raw, min(vsize, rsize) if vsize else rsize, chars))

    def sec(self, va):
        for s in self.secs:
            if s[1] <= va < s[1] + s[3]:
                return s
        return None

    def off(self, va):
        s = self.sec(va)
        return None if s is None else s[2] + va - s[1]

    def u32(self, va):
        return struct.unpack_from("<I", self.d, self.off(va))[0]

    def is_code(self, va):
        s = self.sec(va)
        return s is not None and bool(s[4] & 0x20000000)  # IMAGE_SCN_MEM_EXECUTE

    def cstr_ident(self, va):
        s = self.sec(va)
        if s is None or (s[4] & 0x20000000):
            return None
        o = self.off(va)
        e = self.d.find(b"\0", o, o + 97)
        if e < 0:
            return None
        b = self.d[o:e]
        return b.decode("ascii") if IDENT.match(b) else None


def find_tables(pe, min_run=16):
    """Return runs of (entry_va, name, fn_va) pairs, longest first."""
    runs = []
    for name, va, raw, size, chars in pe.secs:
        if chars & 0x20000000:
            continue
        for align in (0, 4):
            a, cur = va + align, []
            while a + 8 <= va + size:
                p, f = struct.unpack_from("<II", pe.d, pe.off(a))
                nm = pe.cstr_ident(p)
                if nm and pe.is_code(f):
                    cur.append((a, nm, f))
                else:
                    if len(cur) >= min_run:
                        runs.append(cur)
                    cur = []
                a += 8
            if len(cur) >= min_run:
                runs.append(cur)
    uniq = {r[0][0]: r for r in runs}
    return sorted(uniq.values(), key=len, reverse=True)


def count_from_callsite(pe, table_va):
    """Find `call getter; push eax; push table_va` and decode getter `mov eax, imm32; ret`."""
    needle = b"\x50\x68" + struct.pack("<I", table_va)
    hits = []
    for name, va, raw, size, chars in pe.secs:
        if not chars & 0x20000000:
            continue
        blob = pe.d[raw:raw + size]
        i = blob.find(needle)
        while i >= 0:
            site = va + i
            if i >= 5 and blob[i - 5] == 0xE8:
                tgt = (site + struct.unpack_from("<i", blob, i - 4)[0]) & 0xFFFFFFFF
                o = pe.off(tgt)
                if o is not None and pe.d[o] == 0xB8 and pe.d[o + 5] == 0xC3:
                    hits.append((site + 1, tgt, struct.unpack_from("<I", pe.d, o + 1)[0]))
            i = blob.find(needle, i + 1)
    return hits


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "work", "GH3.exe")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "docs", "data")
    with open(exe, "rb") as fh:
        pe = PE(fh.read())

    runs = find_tables(pe)
    if not runs:
        raise SystemExit("no {name, fn} table found")
    table = runs[0]
    tva = table[0][0]
    sites = count_from_callsite(pe, tva)
    count = sites[0][2] if sites else len(table)
    if sites:
        print(f"table 0x{tva:x}: call site 0x{sites[0][0]:x}, count getter 0x{sites[0][1]:x} -> {count}", file=sys.stderr)
    else:
        print(f"table 0x{tva:x}: no count getter found; using heuristic run length {len(table)}", file=sys.stderr)
    if count != len(table):
        print(f"warning: heuristic run {len(table)} != declared count {count}; reading declared count", file=sys.stderr)
        table = []
        for i in range(count):
            p, f = struct.unpack_from("<II", pe.d, pe.off(tva + 8 * i))
            table.append((tva + 8 * i, pe.cstr_ident(p) or f"unnamed_{p:08x}", f))

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "cfuncs.tsv"), "w") as fh:
        for _, nm, f in table:
            fh.write(f"0x{f:08x}\t{nm}\n")
    uniq = len({f for _, _, f in table})
    print(f"cfuncs.tsv: {len(table)} entries, {uniq} unique function addresses", file=sys.stderr)

    # Member-function name list: a char*[] immediately following the table,
    # registered by the next `push eax; push <list>` site.
    mva = tva + 8 * count
    msites = count_from_callsite(pe, mva)
    members = []
    if msites:
        for i in range(msites[0][2]):
            p = pe.u32(mva + 4 * i)
            members.append((p, pe.cstr_ident(p) or f"unnamed_{p:08x}"))
        with open(os.path.join(out, "cmemberfuncs.tsv"), "w") as fh:
            for p, nm in members:
                fh.write(f"0x{p:08x}\t{nm}\n")
        print(f"cmemberfuncs.tsv: {len(members)} member-function names (list 0x{mva:x})", file=sys.stderr)

    for r in runs[1:]:
        print(f"note: secondary run 0x{r[0][0]:x} len {len(r)} ({r[0][1]}..{r[-1][1]})", file=sys.stderr)


if __name__ == "__main__":
    main()
