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
# A few lifted files hold huge straight-line x87 functions (85k+ lines of
# C++ each). clang takes 30+ minutes on them at -O2 and still 30+ at -O1
# for the largest, so: over 5 MB at -O1, over 6.5 MB at -O0.
file(GLOB _gh3_gen CONFIGURE_DEPENDS "${GH3_GENERATED_DIR}/*.cpp")
foreach(_f IN LISTS _gh3_gen)
  file(SIZE "${_f}" _size)
  if(_size GREATER 6500000)
    set_source_files_properties("${_f}" TARGET_DIRECTORY gh3_lifted PROPERTIES COMPILE_OPTIONS -O0)
  elseif(_size GREATER 5000000)
    set_source_files_properties("${_f}" TARGET_DIRECTORY gh3_lifted PROPERTIES COMPILE_OPTIONS -O1)
  endif()
endforeach()
add_executable(gh3 src/main.cpp $<TARGET_OBJECTS:gh3_lifted>)
target_compile_features(gh3 PRIVATE cxx_std_20)
target_link_libraries(gh3 PRIVATE recomp_win32 recomp_d3d9 recomp_dinput8 recomp_xinput recomp_bink)
