// GH3 (BetterGH3) on SwARc: the game's configuration and entry.
//   gh3 <game dir> [exe]   (exe defaults to <game dir>/GH3.exe)

#include <cstdio>
#include <string>

#include "win32/process.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <Guitar Hero III dir> [GH3.exe]\n", argv[0]);
    return 2;
  }
  const std::string game_dir = argv[1];
  const std::string exe = argc > 2 ? argv[2] : game_dir + "/GH3.exe";

  recomp::win32::GameConfig game;
  game.id = "gh3";
  game.guest_dir = "C:\\Program Files\\Aspyr\\Guitar Hero III";
  game.exe_name = "GH3.exe";
  game.fullscreen = recomp::win32::GameConfig::Fullscreen::Window;
  game.video_memory_mb = 256;
  // The VC++ 2005 SP1 CRT (8.0.50727.6195, from Microsoft's redistributable),
  // lifted with the EXE; msvcp80 imports msvcr80, so msvcr80 comes first.
  // FMOD Ex (UPX-unpacked fmodex.dll) imports msvcr80, so it follows it.
  game.lifted_dlls = {
      {.name = "msvcr80.dll", .static_import = true},
      {.name = "msvcp80.dll", .static_import = true},
      {.name = "fmodex.dll", .static_import = true},
  };
  return recomp::RunProcess(game, exe, game_dir);
}
