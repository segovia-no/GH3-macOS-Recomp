// GH3-macOS-Recomp: Guitar Hero III (PC) on SwARc, the game's configuration and entry.
//   gh3 <game dir> [exe]   (exe defaults to <game dir>/GH3.exe)
// Without arguments (the app bundle, packaging/macos/make_app.sh) the game dir is
// the bundle's Resources/game if it has one (--embed-game), else
// ~/Library/Application Support/gh3/game; the log goes to
// ~/Library/Logs/Guitar Hero III.log.

#include <SDL3/SDL.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/stat.h>

#include "runtime/log.h"
#include "win32/process.h"

int main(int argc, char** argv) {
  std::string game_dir;
  if (argc >= 2) {
    game_dir = argv[1];
  } else {
    const char* res = SDL_GetBasePath();  // a bundle's Resources/, with the slash
    if (!res) {
      std::fprintf(stderr, "usage: %s <Guitar Hero III dir> [GH3.exe]\n", argv[0]);
      return 2;
    }
    game_dir = std::string(res) + "game";
    const char* home = std::getenv("HOME");
    struct stat st;
    if (stat(game_dir.c_str(), &st) != 0 && home)
      game_dir = std::string(home) + "/Library/Application Support/gh3/game";
    if (home) {
      const std::string log = std::string(home) + "/Library/Logs/Guitar Hero III.log";
      if (std::freopen(log.c_str(), "w", stderr)) {
        std::setvbuf(stderr, nullptr, _IONBF, 0);
        std::freopen(log.c_str(), "a", stdout);
      }
    }
  }
  // GH3_TRACE=1: log every import call (GH3_TRACE_FILTER narrows it).
  recomp::g_trace = std::getenv("GH3_TRACE") != nullptr;
  // The song clock follows FMOD's stream position, which runs ahead of what
  // is heard by the host's output buffering: SDL's default device buffer
  // (1024 frames at 44.1/48 kHz, double-buffered on CoreAudio) puts the
  // audio ~50 ms behind the notes. 256 frames keeps it to a few ms. An
  // SDL_AUDIO_DEVICE_SAMPLE_FRAMES already in the environment wins.
  setenv("SDL_AUDIO_DEVICE_SAMPLE_FRAMES", "256", 0);
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
