# GH3-macOS-Recomp: Guitar Hero III (PC) for macOS, the game's native build on SwARc.
# Normally driven by ./setup.sh (scripts/setup/build.sh); by hand:
#   cmake -S . -B build/cmake -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
#     -DRECOMP_LLVM_ROOT=$(brew --prefix)/opt/llvm@22
#   cmake --build build/cmake --target gh3
# The lifted sources come from recomp_lift (scripts/setup/lift.sh) in
# GH3_GENERATED_DIR; docs/dev/building.md has the whole pipeline.
cmake_minimum_required(VERSION 3.25)
project(GH3-macOS-Recomp CXX C)

set(SWARC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SwARc" CACHE PATH "SwARc checkout (patched)")
set(GH3_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/generated" CACHE PATH "recomp_lift output")
if(NOT EXISTS "${SWARC_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "No SwARc at ${SWARC_DIR}: run scripts/setup/fetch_swarc.sh (or ./setup.sh)")
endif()
set(CMAKE_LINK_DEPENDS_NO_SHARED ON)
enable_testing()
add_subdirectory("${SWARC_DIR}" swarc)

recomp_add_lifted(gh3_lifted "${GH3_GENERATED_DIR}")
add_executable(gh3
  src/main.cpp
  src/awl.cpp
  src/plugins.cpp
  src/fmod_cpu.cpp
  src/stubs.cpp
  src/skinning.cpp
  $<TARGET_OBJECTS:gh3_lifted>)
target_compile_features(gh3 PRIVATE cxx_std_20)
target_link_libraries(gh3 PRIVATE recomp_win32 recomp_d3d9 recomp_dinput8 recomp_xinput recomp_bink recomp_dsound)

# Native replacements of lifted float code must round exactly like it:
# no FMA contraction, no fast-math (src/skinning.cpp).
set_source_files_properties(src/skinning.cpp PROPERTIES COMPILE_OPTIONS "-ffp-contract=off;-fno-fast-math")
