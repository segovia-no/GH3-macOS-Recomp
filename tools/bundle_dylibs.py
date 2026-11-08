#!/usr/bin/env python3
"""Copies every non-system dylib an executable needs into an app bundle.

  bundle_dylibs.py <App.app/Contents/MacOS/exe> [extra rpath dirs...]

Walks the dependency tree (otool -L), resolving @rpath (the loading
image's LC_RPATHs, the executable's, then the extra dirs), @loader_path and
@executable_path. Copies each library into Contents/Frameworks once,
rewrites every reference to @rpath/<name>, sets each library's id to
@rpath/<name>, and leaves the executable a single rpath,
@executable_path/../Frameworks. System libraries (/usr/lib, /System) stay.
Signatures are left to the caller (codesign after this).
"""

import os
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def deps(path):
    lines = run("otool", "-L", path).splitlines()[1:]
    out = [l.strip().split(" (compatibility")[0] for l in lines if l.strip()]
    # A dylib lists its own id first.
    own = run("otool", "-D", path).splitlines()[1:]
    if own and out and out[0] == own[0].strip():
        out = out[1:]
    return out


def rpaths(path):
    out, lines = [], run("otool", "-l", path).splitlines()
    for i, l in enumerate(lines):
        if l.strip() == "cmd LC_RPATH":
            out.append(lines[i + 2].strip().split(" ")[1])
    return out


def system(ref):
    return ref.startswith("/usr/lib/") or ref.startswith("/System/")


def main():
    exe = os.path.abspath(sys.argv[1])
    extra = sys.argv[2:]
    exe_dir = os.path.dirname(exe)
    fw = os.path.normpath(os.path.join(exe_dir, "..", "Frameworks"))
    os.makedirs(fw, exist_ok=True)
    exe_rpaths = rpaths(exe)

    def resolve(ref, loader, loader_rpaths):
        def sub(p):
            p = p.replace("@loader_path", os.path.dirname(loader))
            return p.replace("@executable_path", exe_dir)

        if ref.startswith("@rpath/"):
            name = ref[len("@rpath/"):]
            for rp in loader_rpaths + exe_rpaths + extra:
                cand = os.path.join(sub(rp), name)
                if os.path.exists(cand):
                    return os.path.realpath(cand)
            sys.exit(f"bundle_dylibs: cannot resolve {ref} (from {loader})")
        p = sub(ref)
        if not os.path.exists(p):
            sys.exit(f"bundle_dylibs: missing {p} (from {loader})")
        return os.path.realpath(p)

    copied = {}  # real source path -> bundled name
    queue = [(exe, exe)]  # (image to scan, its original path for resolving)
    while queue:
        image, orig = queue.pop()
        image_rpaths = rpaths(orig)
        for ref in deps(image):
            if system(ref):
                continue
            src = resolve(ref, orig, image_rpaths)
            name = os.path.basename(ref)
            if src not in copied:
                dst = os.path.join(fw, name)
                if os.path.exists(dst) and name not in copied.values():
                    os.remove(dst)
                shutil.copy2(src, dst)
                os.chmod(dst, 0o755)
                run("install_name_tool", "-id", "@rpath/" + name, dst)
                copied[src] = name
                queue.append((dst, src))
            run("install_name_tool", "-change", ref, "@rpath/" + copied[src], image)
        if image != exe:  # libraries resolve through the executable's rpath
            for rp in rpaths(image):
                run("install_name_tool", "-delete_rpath", rp, image)

    for rp in exe_rpaths:
        run("install_name_tool", "-delete_rpath", rp, exe)
    run("install_name_tool", "-add_rpath", "@executable_path/../Frameworks", exe)
    print(f"bundle_dylibs: {len(copied)} libraries in {fw}")


if __name__ == "__main__":
    main()
