# 0003 — Conan 2 integration path

Status: **partially resolved** (preset mechanism verified; full Conan configure
pending Phase 2 real-tool integration)

## Decision
Conan 2 integration goes through CMakeDeps + CMakeToolchain and Conan's
generated presets, surfaced to Forge via `CMakeUserPresets.json`. Forge calls
`cmake --preset <profile> -B <fingerprinted-dir>` and never assembles toolchain
paths by hand.

## Spike result (Phase 0 + Phase 2)
- CMake 4.4 accepts `cmake --preset debug -S . -B <other-dir>`: the `-B` flag
  **overrides** `binaryDir` from the preset. This lets Forge keep
  `target/<profile>-<fingerprint>/` directories while still configuring through
  a preset. Verified on macOS.
- Real Conan 2.33 `conan install . -of <build-dir> -s build_type=Debug`
  generates a `CMakePresets.json` with a `conan-debug` preset **inside the
  output folder's `generators/` directory**, not in the source root. It is not
  directly usable with a source-root `cmake --preset` call.
- **Resolved integration:** Forge still configures via its own preset
  (`cmake --preset <profile> -B <fingerprinted-dir>`) and passes Conan's
  generated `conan_toolchain.cmake` with `-DCMAKE_TOOLCHAIN_FILE=<discovered>`.
  This is a documented, minimal deviation from "never pass toolchain paths by
  hand": the path is discovered from Conan's output, never constructed from
  user input, and `CMakeUserPresets.json` remains fully user-owned.
- Fingerprint inputs (hashed together): compiler ID/version, generator,
  architecture, Conan host/build profile contents, sanitizer flags, and the
  contents of any explicit `--toolchain` file. Debug and release are always
  separate directories.
- `forge build` skips Conan entirely when no Conan dependencies are declared.
