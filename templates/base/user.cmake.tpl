# Set local CMake overrides here. Forge sync preserves this file.

# Optional static analysis, adapted from the Valhalla-server project.
# Both are OFF by default so a fresh build is never slowed by analysis tools.
option(FORGE_CLANG_TIDY "Run clang-tidy while compiling" OFF)
option(FORGE_CPPCHECK "Run cppcheck while compiling" OFF)

if(FORGE_CLANG_TIDY)
  find_program(FORGE_CLANG_TIDY_EXE NAMES clang-tidy)
  if(FORGE_CLANG_TIDY_EXE)
    set(CMAKE_CXX_CLANG_TIDY "${FORGE_CLANG_TIDY_EXE}"
      --config-file="${CMAKE_SOURCE_DIR}/.clang-tidy")
  endif()
endif()

if(FORGE_CPPCHECK)
  find_program(FORGE_CPPCHECK_EXE NAMES cppcheck)
  if(FORGE_CPPCHECK_EXE)
    set(CMAKE_CXX_CPPCHECK "${FORGE_CPPCHECK_EXE}"
      --enable=warning,performance,portability
      --inline-suppr
      --suppressions-list="${CMAKE_SOURCE_DIR}/cppcheck.supp")
  endif()
endif()
