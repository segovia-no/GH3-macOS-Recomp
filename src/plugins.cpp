// The GH3+ plugin hook. This GH3.exe calls a stub patched into
// the last page of .text (0x897d40, called from WinMain at 0x4016de) that
// does LoadLibraryA("PLUGINS\core.dll") and exits if it fails; core.dll
// then loads every PLUGINS\*.dll, each patching GH3.exe in memory. Those
// x86 DLLs cannot run here: the stub is replaced (`replace 00897d40` in
// manifests/overrides.manifest) and becomes where native ports of the plugins
// install themselves. None are ported yet.

#include "x86/lifted.h"

namespace recomp::gen {

void f_00897D40(::recomp::Ctx& c) {
  c.eax = 1;   // a non-null module handle: the stub's success path
  c.esp += 4;  // ret
}

}  // namespace recomp::gen
