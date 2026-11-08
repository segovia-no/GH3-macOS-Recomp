# GH3 (BetterGH3) native build on SwARc.
#   cmake -S recomp -B work/build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
#     -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
#     -DRECOMP_LLVM_ROOT=/opt/homebrew/opt/llvm@22
#   cmake --build work/build
# Lifted sources come from recomp_lift (see docs/spike-swarc.md) into GH3_GENERATED_DIR.
cmake_minimum_required(VERSION 3.25)
project(gh3recomp CXX C)

set(SWARC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../ref/SwARc" CACHE PATH "SwARc checkout")
set(GH3_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../work/generated" CACHE PATH "recomp_lift output")
set(CMAKE_LINK_DEPENDS_NO_SHARED ON)
enable_testing()
add_subdirectory("${SWARC_DIR}" swarc)

recomp_add_lifted(gh3_lifted "${GH3_GENERATED_DIR}")
# GH3.exe is lifted with --no-x87-doubles (tools/lift.sh): its float code
# runs at PC=24, where the host-double path is never taken, and without it
# clang builds even the Havok solver's 12k-instruction functions at -O2
# (~8 min each instead of not finishing).
add_executable(gh3 src/main.cpp src/awl.cpp src/plugins.cpp src/fmod_cpu.cpp $<TARGET_OBJECTS:gh3_lifted>)
target_compile_features(gh3 PRIVATE cxx_std_20)
target_link_libraries(gh3 PRIVATE recomp_win32 recomp_d3d9 recomp_dinput8 recomp_xinput recomp_bink recomp_dsound)
