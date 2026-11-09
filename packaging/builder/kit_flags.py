#!/usr/bin/env python3
"""Reads `ninja -t commands gh3` for the builder kit (make_kit.sh).

  ninja -C <build> -t commands gh3 | kit_flags.py --targets
      the ninja targets gh3 needs except the lifted code: its libraries
      that the build makes and the objects of src/ and lifted_table.cpp
  ninja -C <build> -t commands gh3 | kit_flags.py --link-paths
      the libraries gh3 links, as absolute paths (relative ones against
      $CMAKE_BUILD)
  ninja -C <build> -t commands gh3 | kit_flags.py <kit>
      writes <kit>/cxxflags: the flags of a lifted file's compile (gen_000.cpp)
      without its include paths, dependency output and file names; and
      <kit>/link: the libraries, one per line, as the file names they have in
      <kit>/Frameworks (each library's install name, which bundle_dylibs.py
      kept as its name)
"""

import os
import subprocess
import sys

cmds = sys.stdin.read().splitlines()
build = os.environ.get("CMAKE_BUILD", "build/cmake")
link = next(c for c in cmds if " -o gh3 " in c)
dylibs = [a for a in link.split() if a.endswith(".dylib")]


def output(cmd):
    args = cmd.split()
    return args[args.index("-o") + 1]


if sys.argv[1] == "--targets":
    objs = [output(c) for c in cmds if " -c " in c and
            ("/src/" in c and "CMakeFiles/gh3.dir/" in c or "/x86/lifted_table.cpp" in c)]
    print("\n".join([d for d in dylibs if not os.path.isabs(d)] + objs))
    sys.exit()

paths = [d if os.path.isabs(d) else os.path.join(build, d) for d in dylibs]
if sys.argv[1] == "--link-paths":
    print("\n".join(paths))
    sys.exit()

kit = sys.argv[1]
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

libs = []
for a, path in zip(dylibs, paths):
    ident = subprocess.run(["otool", "-D", path], capture_output=True, text=True).stdout.splitlines()
    name = os.path.basename(ident[1].strip()) if len(ident) > 1 else os.path.basename(a)
    if not os.path.exists(os.path.join(kit, "Frameworks", name)):
        sys.exit(f"kit_flags: {name} (from {a}) is not in the kit")
    libs.append(name)
with open(os.path.join(kit, "link"), "w") as f:
    f.write("\n".join(libs) + "\n")
print(f"kit_flags: {len(flags)} flags, {len(libs)} libraries")
