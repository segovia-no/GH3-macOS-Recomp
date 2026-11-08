#!/usr/bin/env python3
"""Compare GH3.exe imports against the HLE handlers SwARc registers.

Usage:
  python3 -I tools/import_coverage.py <imports.tsv> <swarc_win32_src_dir> [--out file.tsv]

imports.tsv comes from SwARc's tools/pe_symbols.py (iat_va, dll, symbol).
HLE handlers are found by scanning for HLE("dll", Name, argc) in the sources.
Prints a per-DLL summary; --out writes one row per import with its status.
"""
import argparse
import collections
import os
import re
import sys

# HLE(dll, Name, n) / HLE64(dll, Name, n): identifier is the export name.
HLE_RE = re.compile(r'\bHLE(?:64)?\(\s*"([^"]+)"\s*,\s*([A-Za-z0-9_@?$]+)\s*,')
# HLE_NAMED(dll, "export", ident, n) / HLE_NAMED_X(...): quoted export name.
HLE_NAMED_RE = re.compile(r'\bHLE_NAMED(?:_X)?\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,')


def load_imports(path):
    rows = []
    with open(path) as f:
        next(f)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 3:
                rows.append((parts[0], parts[1].lower(), parts[2]))
    return rows


def load_hle(src_dir):
    have = set()
    for root, _, files in os.walk(src_dir):
        for name in files:
            if not name.endswith((".cpp", ".h", ".inc")):
                continue
            with open(os.path.join(root, name), errors="replace") as f:
                text = f.read()
                for rx in (HLE_RE, HLE_NAMED_RE):
                    for dll, fn in rx.findall(text):
                        have.add((dll.lower(), fn))
    return have


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("imports")
    ap.add_argument("src")
    ap.add_argument("--out")
    a = ap.parse_args()

    imports = load_imports(a.imports)
    have = load_hle(a.src)
    hle_dlls = {d for d, _ in have}

    per = collections.OrderedDict()
    out = []
    for va, dll, sym in imports:
        if (dll, sym) in have:
            status = "hle"
        elif dll in hle_dlls:
            status = "missing"
        else:
            status = "no-module"
        per.setdefault(dll, collections.Counter())[status] += 1
        out.append((va, dll, sym, status))

    print(f"{'dll':24} {'total':>5} {'hle':>5} {'missing':>7} {'no-module':>9}")
    tot = collections.Counter()
    for dll, c in sorted(per.items(), key=lambda kv: -sum(kv[1].values())):
        n = sum(c.values())
        tot.update(c)
        print(f"{dll:24} {n:5} {c['hle']:5} {c['missing']:7} {c['no-module']:9}")
    n = sum(tot.values())
    print(f"{'TOTAL':24} {n:5} {tot['hle']:5} {tot['missing']:7} {tot['no-module']:9}")

    if a.out:
        with open(a.out, "w") as f:
            f.write("iat_va\tdll\tsymbol\tstatus\n")
            for row in out:
                f.write("\t".join(row) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
