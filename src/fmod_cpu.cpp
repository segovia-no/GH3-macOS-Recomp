// FMOD Ex's CPU feature probes (fmodex.dll, lifted), replaced to report no
// SIMD so FMOD mixes with its plain C code: its MMX, SSE and 3DNow! paths
// use instructions the lifter does not implement (manifests/fmodex.manifest).
// All three are cdecl with no arguments.

#include "x86/lifted.h"

namespace recomp::gen {

// 0x10029740: CPUID(1).EDX bit 25 (SSE) as 0/1.
void f_10029740(::recomp::Ctx& c) {
  c.eax = 0;
  c.esp += 4;  // ret
}

// 0x1009b87e: CPUID(1).EDX (feature flags incl. MMX), 0 if no CPUID.
void f_1009B87E(::recomp::Ctx& c) {
  c.eax = 0;
  c.esp += 4;
}

// 0x1009b89a: CPUID(0x80000001).EDX (3DNow!, MMX extensions).
void f_1009B89A(::recomp::Ctx& c) {
  c.eax = 0;
  c.esp += 4;
}

}  // namespace recomp::gen
