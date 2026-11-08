// Aspyr's AWL.dll (Aspyr::Win), the PC port's thin OS layer, reimplemented
// natively: the 20 exports GH3.exe imports. Behaviour from the shipped
// AWL.dll (decompiled locally with Ghidra, scripts/dev/ghidra/DecompileAt.java):
// - Init(Mode) returns Error; GH3 treats 12 as success, anything else goes
//   to ShowErrorMessage + TerminateProcess.
// - Path/language/title/version getters copy a cached string into the
//   caller's buffer and return it. GetLanguage is a two-letter code
//   (GH3 compares its first two characters with "fr", "de", ...).
// - Config{Number,String} are a key/value store ("Video.Width",
//   "Sound.SongSkew", ...) whose getters return the caller's default for
//   missing keys. AWL keeps it in AspyrConfig.xml; here it is
//   <data dir>/AspyrConfig.ini, one `key=value` per line.
// - Video.Width/Height default to the largest 16:9 display mode within 85%
//   of the desktop (the game's own default, 1024x768, is a tiny window on
//   a high-density display: SwARc sizes windows in pixels). GH3_RESOLUTION
//   =WxH overrides it; a value saved in the config file wins over both.
// - DefWindowProcA tracks activation for IsActive and forwards to user32.
// - GetConfigNumber returns a double in ST0 (cdecl), so it pushes onto the
//   guest's x87 stack.

#include <bit>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <mutex>
#include <string>

#include "win32/hle.h"
#include "win32/process.h"
#include "win32/user32_window.h"
#include "win32/win32.h"
#include "x86/runtime.h"
#include "x86/x87.h"

namespace recomp::hle {
namespace {

constexpr uint32_t kAwlInitOk = 12;
constexpr uint32_t WM_ACTIVATEAPP = 0x001C;

// Guest paths; the Win32 layer maps them into the per-user tree.
constexpr const char* kPathUserVisible =
    "C:\\Users\\Player\\Documents\\Aspyr\\Guitar Hero III";
constexpr const char* kPathUserNonVisible =
    "C:\\Users\\Player\\AppData\\Local\\Aspyr\\Guitar Hero III";
constexpr const char* kPathTemp = "C:\\Users\\Player\\AppData\\Local\\Temp";
constexpr const char* kTitle = "Guitar Hero III";
constexpr const char* kFullVersion = "1.3.1.68131";

std::mutex g_cfg_mu;
std::map<std::string, std::string> g_cfg;
bool g_cfg_loaded = false;
bool g_active = true;

std::string ConfigPath() { return DataDir() + "/AspyrConfig.ini"; }

void LoadConfig() {
  if (g_cfg_loaded) return;
  g_cfg_loaded = true;
  std::ifstream f(ConfigPath());
  std::string line;
  while (std::getline(f, line)) {
    size_t eq = line.find('=');
    if (eq != std::string::npos) g_cfg[line.substr(0, eq)] = line.substr(eq + 1);
  }
}

void SaveConfig() {
  std::ofstream f(ConfigPath(), std::ios::trunc);
  for (const auto& [k, v] : g_cfg) f << k << '=' << v << '\n';
}

// The default render size (see the top of the file).
ModeSize DefaultResolution() {
  static const ModeSize size = [] {
    int w = 0, h = 0;
    if (const char* e = Env("RESOLUTION"); e && std::sscanf(e, "%dx%d", &w, &h) == 2 &&
                                          w > 0 && h > 0)
      return ModeSize{w, h};
    std::vector<ModeSize> modes = DisplayModeSizes();
    ModeSize desktop{1024, 768}, best{1024, 768};
    for (const ModeSize& m : modes)
      if (int64_t(m.w) * m.h > int64_t(desktop.w) * desktop.h) desktop = m;
    for (const ModeSize& m : modes)
      if (m.w * 9 == m.h * 16 && m.w * 100 <= desktop.w * 85 && m.h * 100 <= desktop.h * 85 &&
          m.w > best.w)
        best = m;
    return best;
  }();
  return size;
}

double GetNumber(const std::string& key, double def) {
  if (key == "Video.Width" || key == "Video.Height") {
    const ModeSize r = DefaultResolution();
    def = key == "Video.Width" ? r.w : r.h;
  }
  std::lock_guard<std::mutex> l(g_cfg_mu);
  LoadConfig();
  auto it = g_cfg.find(key);
  return it == g_cfg.end() ? def : std::strtod(it->second.c_str(), nullptr);
}

void SetNumber(const std::string& key, double v) {
  std::lock_guard<std::mutex> l(g_cfg_mu);
  LoadConfig();
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.17g", v);
  g_cfg[key] = buf;
  SaveConfig();
}

// A cdecl double argument at stack slot i (two slots).
double ArgDouble(Ctx& c, int i) {
  return std::bit_cast<double>(uint64_t(Arg(c, i)) | uint64_t(Arg(c, i + 1)) << 32);
}

// cdecl double return: ST0.
uint32_t RetSt0(Ctx& c, double v) {
  x87::LoadF64(c.fpu, std::bit_cast<uint64_t>(v));
  return 0;
}

// char* getters: copy s into the caller's buffer and return it.
uint32_t CopyA(Ctx& c, const std::string& s) {
  PutStr(Arg(c, 0), s);
  return Arg(c, 0);
}

std::string Language() {
  const char* l = Env("LANGUAGE");
  return l && *l ? l : "en";
}

}  // namespace

HLE_NAMED("awl.dll", "?Init@Win@Aspyr@@YA?AW4Error@12@W4Mode@12@@Z", AwlInit, 0) {
  return kAwlInitOk;
}

HLE_NAMED("awl.dll", "?ExitProcess@Win@Aspyr@@YAXI@Z", AwlExitProcess, 0) {
  std::fflush(nullptr);
  std::_Exit(int(Arg(c, 0)));
}

HLE_NAMED("awl.dll", "?TerminateProcess@Win@Aspyr@@YAXI@Z", AwlTerminateProcess, 0) {
  std::fflush(nullptr);
  std::_Exit(int(Arg(c, 0)));
}

HLE_NAMED("awl.dll", "?ShowErrorMessage@Win@Aspyr@@YAXW4Error@12@@Z", AwlShowErrorMessage,
          0) {
  std::fprintf(stderr, "awl: ShowErrorMessage(error %u)\n", uint32_t(Arg(c, 0)));
  return 0;
}

HLE_NAMED("awl.dll", "?IsActive@Win@Aspyr@@YA_NXZ", AwlIsActive, 0) { return g_active; }

// (hwnd, msg, wparam, lparam), cdecl.
HLE_NAMED("awl.dll", "?DefWindowProcA@Win@Aspyr@@YAJPAUHWND__@@IIJ@Z", AwlDefWindowProcA, 0) {
  uint32_t hwnd = Arg(c, 0), msg = Arg(c, 1), wp = Arg(c, 2), lp = Arg(c, 3);
  if (msg == WM_ACTIVATEAPP) g_active = wp != 0;
  uint32_t def = ProcAddress(ModuleHandle("user32.dll"), "DefWindowProcA");
  return uint32_t(CallGuest(c, def, {hwnd, msg, wp, lp}));
}

HLE_NAMED("awl.dll", "?GetPathUserVisible@Win@Aspyr@@YAPADPAD@Z", AwlGetPathUserVisible, 0) {
  return CopyA(c, kPathUserVisible);
}
HLE_NAMED("awl.dll", "?GetPathUserNonVisible@Win@Aspyr@@YAPADPAD@Z", AwlGetPathUserNonVisible,
          0) {
  return CopyA(c, kPathUserNonVisible);
}
HLE_NAMED("awl.dll", "?GetPathTemp@Win@Aspyr@@YAPADPAD@Z", AwlGetPathTemp, 0) {
  return CopyA(c, kPathTemp);
}
HLE_NAMED("awl.dll", "?GetPathInstall@Win@Aspyr@@YAPADPAD@Z", AwlGetPathInstall, 0) {
  return CopyA(c, Game().guest_dir);
}
HLE_NAMED("awl.dll", "?GetLanguage@Win@Aspyr@@YAPADPAD@Z", AwlGetLanguage, 0) {
  return CopyA(c, Language());
}
HLE_NAMED("awl.dll", "?GetFullVersion@Win@Aspyr@@YAPADPAD@Z", AwlGetFullVersion, 0) {
  return CopyA(c, kFullVersion);
}
HLE_NAMED("awl.dll", "?GetTitle@Win@Aspyr@@YAPA_WPA_W@Z", AwlGetTitle, 0) {
  PutWStr(Arg(c, 0), kTitle);
  return Arg(c, 0);
}

// (IUnknown* device, DWORD object offset, wchar_t* out): the object's
// display name. The game only shows it in its controller settings.
HLE_NAMED("awl.dll", "?GetDirectInputObjectName@Win@Aspyr@@YAPA_WPAUIUnknown@@KPA_W@Z",
          AwlGetDirectInputObjectName, 0) {
  char buf[32];
  std::snprintf(buf, sizeof buf, "Object %u", uint32_t(Arg(c, 1)));
  PutWStr(Arg(c, 2), buf);
  return Arg(c, 2);
}

// (const char* key, double default) / (const wchar_t* key, double default)
HLE_NAMED("awl.dll", "?GetConfigNumber@Win@Aspyr@@YANPBDN@Z", AwlGetConfigNumberA, 0) {
  return RetSt0(c, GetNumber(GStr(Arg(c, 0)), ArgDouble(c, 1)));
}
HLE_NAMED("awl.dll", "?GetConfigNumber@Win@Aspyr@@YANPB_WN@Z", AwlGetConfigNumberW, 0) {
  return RetSt0(c, GetNumber(win32::Narrow(GWStr(Arg(c, 0))), ArgDouble(c, 1)));
}
HLE_NAMED("awl.dll", "?SetConfigNumber@Win@Aspyr@@YAXPBDN@Z", AwlSetConfigNumberA, 0) {
  SetNumber(GStr(Arg(c, 0)), ArgDouble(c, 1));
  return 0;
}
HLE_NAMED("awl.dll", "?SetConfigNumber@Win@Aspyr@@YAXPB_WN@Z", AwlSetConfigNumberW, 0) {
  SetNumber(win32::Narrow(GWStr(Arg(c, 0))), ArgDouble(c, 1));
  return 0;
}

// (const char* key, char* out, const char* default) -> out
HLE_NAMED("awl.dll", "?GetConfigString@Win@Aspyr@@YAPADPBDPAD0@Z", AwlGetConfigString, 0) {
  std::string key = GStr(Arg(c, 0)), v = Arg(c, 2) ? GStr(Arg(c, 2)) : "";
  {
    std::lock_guard<std::mutex> l(g_cfg_mu);
    LoadConfig();
    if (auto it = g_cfg.find(key); it != g_cfg.end()) v = it->second;
  }
  PutStr(Arg(c, 1), v);
  return Arg(c, 1);
}

// (const char* key, const char* value)
HLE_NAMED("awl.dll", "?SetConfigString@Win@Aspyr@@YAXPBD0@Z", AwlSetConfigString, 0) {
  std::lock_guard<std::mutex> l(g_cfg_mu);
  LoadConfig();
  g_cfg[GStr(Arg(c, 0))] = GStr(Arg(c, 1));
  SaveConfig();
  return 0;
}

}  // namespace recomp::hle
