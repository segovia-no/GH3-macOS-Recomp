#!/usr/bin/env python3
"""Removes the kit's libraries that nothing in it loads any more.

  kit_prune.py <kit>

Roots: the kit's bin/ executables and the libraries the game links (the
link file, if it exists yet, else every librecomp_* library). Follows
@rpath references into <kit>/Frameworks and deletes every library outside
that closure (e.g. the GPL FFmpeg's encoders, once the LGPL FFmpeg
replaces it).
"""

import os
import subprocess
import sys

kit = sys.argv[1]
fw = os.path.join(kit, "Frameworks")


def refs(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout
    names = []
    for line in out.splitlines()[1:]:
        ref = line.strip().split(" (")[0]
        if ref.startswith("@rpath/"):
            names.append(ref[len("@rpath/"):])
    return names


roots = [os.path.join(kit, "bin", b) for b in os.listdir(os.path.join(kit, "bin"))]
link = os.path.join(kit, "link")
libs = open(link).read().split() if os.path.exists(link) else [
    n for n in os.listdir(fw) if n.startswith("librecomp_")]
roots += [os.path.join(fw, n) for n in libs]

keep, todo = set(), list(roots)
while todo:
    p = todo.pop()
    for n in refs(p):
        if n not in keep:
            keep.add(n)
            q = os.path.join(fw, n)
            if not os.path.exists(q):
                sys.exit(f"kit_prune: {os.path.basename(p)} needs {n}, which is not in the kit")
            todo.append(q)
keep |= {os.path.basename(r) for r in roots}

removed = sorted(n for n in os.listdir(fw) if n not in keep)
for n in removed:
    os.remove(os.path.join(fw, n))
print(f"kit_prune: kept {len([n for n in os.listdir(fw)])} libraries, removed {len(removed)}: {' '.join(removed)}")
