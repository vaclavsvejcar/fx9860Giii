# Configure and build with:  fxsdk build-fx
# (fxsdk provides the SH toolchain file and the fxSDK CMake modules)

cmake_minimum_required(VERSION 3.15)
project(Penumbra C)

include(GenerateG1A)
include(Fxconv)
find_package(Gint 2.9 REQUIRED)

set(SOURCES
  src/main.c
  src/ui.c
  src/dilution.c
)

add_executable(penumbra ${SOURCES})
target_compile_options(penumbra PRIVATE -Wall -Wextra -Os -g -flto)
target_link_libraries(penumbra Gint::Gint)

# fx-9860G add-in. The internal NAME is limited to 8 characters ("Penumbra" fits).
generate_g1a(TARGET penumbra OUTPUT "Penumbra.g1a"
  NAME "Penumbra" ICON assets-fx/icon.png)
