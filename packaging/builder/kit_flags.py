#!/usr/bin/env python3
"""Writes the builder kit's cxxflags and link files from `ninja -t commands gh3`.

  ninja -C build/cmake -t commands gh3 | kit_flags.py <kit>

cxxflags: the flags of a lifted file's compile (gen_000.cpp) without its
include paths, dependency output and file names. link: the libraries the
game links, one per line, as the file names they have in <kit>/Frameworks
(each library's install name, which bundle_dylibs.py kept as its name).
"""

import os
import subprocess
import sys

kit = sys.argv[1]
cmds = sys.stdin.read().splitlines()

gen = next(c for c in cmds if "/generated/gen_000.cpp" in c and " -c " in c)
args, flags, skip = gen.split()[1:], [], False
for a in args:
    if skip:
        skip = False
    elif a in ("-o", "-MT", "-MF", "-c"):
        skip = True
    elif not (a.startswith("-I") or a == "-MD"):
        flags.append(a)
with open(os.path.join(kit, "cxxflags"), "w") as f:
    f.write(" ".join(flags) + "\n")

link = next(c for c in cmds if " -o gh3 " in c)
libs = []
for a in link.split():
    if not a.endswith(".dylib"):
        continue
    path = a if os.path.isabs(a) else os.path.join(os.environ.get("CMAKE_BUILD", "build/cmake"), a)
    ident = subprocess.run(["otool", "-D", path], capture_output=True, text=True).stdout.splitlines()
    name = os.path.basename(ident[1].strip()) if len(ident) > 1 else os.path.basename(a)
    if not os.path.exists(os.path.join(kit, "Frameworks", name)):
        sys.exit(f"kit_flags: {name} (from {a}) is not in the kit")
    libs.append(name)
with open(os.path.join(kit, "link"), "w") as f:
    f.write("\n".join(libs) + "\n")
print(f"kit_flags: {len(flags)} flags, {len(libs)} libraries")
