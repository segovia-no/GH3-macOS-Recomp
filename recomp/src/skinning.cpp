// GH3's CPU skinning of character meshes (0x61c590), replaced by native
// code (`replace 0061c590` in recomp/overrides.manifest). The lifted body
// stays as f_0061C590_lifted, the reference: GH3_VERIFY_SKIN=1 runs both
// on every call and reports any difference.
//
// Behaviour (from the disassembly; the decompilation in work/song_decomp.c
// keeps the float grouping):
// - Calling convention: out (16-byte aligned) in edx; stack: bones (4x4
//   float matrices, 64 bytes each), header, min, max (16 bytes each); the
//   caller pops the arguments; returns the vertex count in eax.
// - header: +4/+8/+0xc the number of 1-, 2- and 3-bone groups; groups
//   follow from +0x10, each a 16-byte header {int count; int8 bone index at
//   +4 (+5, +6)} then `count` vertices of 14 floats: rows X, Y, Z of four
//   columns (position, normal, tangent, binormal), then weights wA, wB.
// - Per bone, row r (x, y, z) of column k: (X[k]*m[r] + Y[k]*m[4+r]) +
//   Z[k]*m[8+r], plus the translation m[12+r] for the position. Two bones:
//   A*wA + B*wB. Three bones, with wC = (1 - wA) - wB: x and z rows
//   (C*wC + B*wB) + A*wA, the y row (C*wC + A*wA) + B*wB.
// - Normal, tangent and binormal are scaled by RSQRTPS of their squared
//   length ((y*y + x*x) + z*z); the position is not.
// - Output per vertex, three 16-byte stores: px py pz nx | ny nz tx ty |
//   tz bx by bz. The running min and max (MINPS/MAXPS against the values
//   in min/max) are over the first store, normal x included.
// Every lane is the same IEEE operation in the same order as the original,
// so the results are its bits (RSQRTPS through SwARc's model of it). MXCSR:
// PE is set as the original does for any vertex (other flags, which only
// denormal or non-finite data could raise, are not modelled here).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "x86/lifted.h"
#include "x86/sse.h"

namespace recomp::gen {

void f_0061C590_lifted(::recomp::Ctx& c);

namespace {

constexpr uint32_t kMxcsrPE = 0x20;

inline float LdF(const uint8_t* p) {
  float v;
  std::memcpy(&v, p, 4);
  return v;
}

inline float Rsqrt(float x) {
  uint32_t b;
  std::memcpy(&b, &x, 4);
  uint32_t r = ::recomp::sse::RsqrtLaneFast(b);
  float f;
  std::memcpy(&f, &r, 4);
  return f;
}

// One bone's row r for all four columns (lane 0 gets the translation).
inline void BoneRow(const float* m, int r, const float* X, const float* Y, const float* Z,
                    float* out) {
  for (int k = 0; k < 4; k++) out[k] = (X[k] * m[r] + Y[k] * m[4 + r]) + Z[k] * m[8 + r];
  out[0] = out[0] + m[12 + r];
}

struct Skinned {
  uint32_t count = 0;
  float mn[4], mx[4];
};

// Skins every vertex; writes 48 bytes per vertex to `out` (host memory).
Skinned Skin(const uint8_t* B, uint32_t bones, uint32_t header, uint8_t* out,
             const float* mn0, const float* mx0) {
  Skinned s;
  std::memcpy(s.mn, mn0, 16);
  std::memcpy(s.mx, mx0, 16);
  uint32_t g = header + 0x10;  // the first group header
  for (int nb = 1; nb <= 3; nb++) {
    uint32_t groups = ::recomp::lift::Rd<uint32_t>(B, header + 4u * uint32_t(nb));
    for (; groups; groups--) {
      const uint32_t count = ::recomp::lift::Rd<uint32_t>(B, g);
      float ma[16], mb[16], mc[16];
      auto matrix = [&](int i, float* m) {
        const int8_t idx = int8_t(B[g + 4 + uint32_t(i)]);
        std::memcpy(m, B + bones + uint32_t(int32_t(idx) * 0x40), 64);
      };
      matrix(0, ma);
      if (nb >= 2) matrix(1, mb);
      if (nb >= 3) matrix(2, mc);
      s.count += count;
      uint32_t v = g + 0x10;
      for (uint32_t n = count; n; n--, v += 56) {
        float X[4], Y[4], Z[4];
        std::memcpy(X, B + v, 16);
        std::memcpy(Y, B + v + 16, 16);
        std::memcpy(Z, B + v + 32, 16);
        float R[3][4];
        if (nb == 1) {
          for (int r = 0; r < 3; r++) BoneRow(ma, r, X, Y, Z, R[r]);
        } else {
          const float wa = LdF(B + v + 48), wb = LdF(B + v + 52);
          for (int r = 0; r < 3; r++) {
            float a[4], b[4];
            BoneRow(ma, r, X, Y, Z, a);
            BoneRow(mb, r, X, Y, Z, b);
            if (nb == 2) {
              for (int k = 0; k < 4; k++) R[r][k] = a[k] * wa + b[k] * wb;
            } else {
              const float wc = (1.0f - wa) - wb;
              float cc[4];
              BoneRow(mc, r, X, Y, Z, cc);
              for (int k = 0; k < 4; k++)
                R[r][k] = r == 1 ? (cc[k] * wc + a[k] * wa) + b[k] * wb
                                 : (cc[k] * wc + b[k] * wb) + a[k] * wa;
            }
          }
        }
        float rs[4];
        for (int k = 1; k < 4; k++)
          rs[k] = Rsqrt((R[1][k] * R[1][k] + R[0][k] * R[0][k]) + R[2][k] * R[2][k]);
        const float o[12] = {R[0][0],         R[1][0],         R[2][0],         rs[1] * R[0][1],
                             rs[1] * R[1][1], rs[1] * R[2][1], rs[2] * R[0][2], rs[2] * R[1][2],
                             rs[2] * R[2][2], rs[3] * R[0][3], rs[3] * R[1][3], rs[3] * R[2][3]};
        for (int k = 0; k < 4; k++) {
          s.mn[k] = o[k] < s.mn[k] ? o[k] : s.mn[k];
          s.mx[k] = o[k] > s.mx[k] ? o[k] : s.mx[k];
        }
        std::memcpy(out, o, 48);
        out += 48;
      }
      g = v;  // the next group header follows the vertices
    }
  }
  return s;
}

bool VerifyMode() {
  static const bool on = std::getenv("GH3_VERIFY_SKIN") != nullptr;
  return on;
}

}  // namespace

void f_0061C590(::recomp::Ctx& c) {
  uint8_t* const B = ::recomp::g_guest_base;
  const uint32_t esp = c.esp;
  const uint32_t out = c.edx;
  const uint32_t bones = ::recomp::lift::Rd<uint32_t>(B, esp + 4);
  const uint32_t header = ::recomp::lift::Rd<uint32_t>(B, esp + 8);
  const uint32_t pmin = ::recomp::lift::Rd<uint32_t>(B, esp + 12);
  const uint32_t pmax = ::recomp::lift::Rd<uint32_t>(B, esp + 16);
  // MOVNTPS faults on a misaligned output: keep the original's behaviour.
  if (out & 15) return f_0061C590_lifted(c);

  float mn0[4], mx0[4];
  std::memcpy(mn0, B + pmin, 16);
  std::memcpy(mx0, B + pmax, 16);

  if (!VerifyMode()) {
    const Skinned s = Skin(B, bones, header, B + out, mn0, mx0);
    std::memcpy(B + pmin, s.mn, 16);
    std::memcpy(B + pmax, s.mx, 16);
    if (s.count) c.mxcsr |= kMxcsrPE;
    c.eax = s.count;
    c.esp = esp + 4;  // ret
    return;
  }

  // Verification: native into a host buffer, then the original for real.
  static uint64_t calls = 0, bad = 0;
  std::vector<uint8_t> mine;
  uint32_t total = 0;
  {
    // Size the buffer from the vertex counts before skinning.
    uint32_t g = header + 0x10;
    for (int nb = 1; nb <= 3; nb++)
      for (uint32_t groups = ::recomp::lift::Rd<uint32_t>(B, header + 4u * uint32_t(nb));
           groups; groups--) {
        const uint32_t n = ::recomp::lift::Rd<uint32_t>(B, g);
        total += n;
        g += 0x10 + n * 56;
      }
    mine.assign(size_t(total) * 48, 0);
  }
  const Skinned s = Skin(B, bones, header, mine.data(), mn0, mx0);
  f_0061C590_lifted(c);
  calls++;
  bool ok = c.eax == s.count && std::memcmp(B + pmin, s.mn, 16) == 0 &&
            std::memcmp(B + pmax, s.mx, 16) == 0 &&
            std::memcmp(B + out, mine.data(), mine.size()) == 0;
  if (!ok) {
    bad++;
    if (bad <= 10) {
      std::fprintf(stderr, "skin verify: MISMATCH call %llu (%u vertices, eax %u vs %u)\n",
                   (unsigned long long)calls, total, c.eax, s.count);
      for (size_t i = 0; i < mine.size(); i += 4) {
        uint32_t a, b;
        std::memcpy(&a, B + out + i, 4);
        std::memcpy(&b, mine.data() + i, 4);
        if (a != b) {
          std::fprintf(stderr, "  vertex %zu float %zu: lifted %08X native %08X\n", i / 48,
                       (i % 48) / 4, a, b);
          break;
        }
      }
      for (int k = 0; k < 4; k++) {
        uint32_t a, b;
        std::memcpy(&a, B + pmin + 4 * k, 4);
        std::memcpy(&b, &s.mn[k], 4);
        if (a != b) std::fprintf(stderr, "  min[%d]: lifted %08X native %08X\n", k, a, b);
        std::memcpy(&a, B + pmax + 4 * k, 4);
        std::memcpy(&b, &s.mx[k], 4);
        if (a != b) std::fprintf(stderr, "  max[%d]: lifted %08X native %08X\n", k, a, b);
      }
    }
  }
  if ((calls & (calls - 1)) == 0)  // 1, 2, 4, 8, ...
    std::fprintf(stderr, "skin verify: %llu calls, %llu mismatches\n",
                 (unsigned long long)calls, (unsigned long long)bad);
}

}  // namespace recomp::gen
