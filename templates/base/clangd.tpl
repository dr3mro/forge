# clangd project configuration.
# Adapted from the Valhalla-server project (.clangd).
# This is a clangd config file, not a list of command-line flags. Editor launch
# arguments (--background-index, -j, --completion-style, ...) belong in the
# editor's clangd settings.
---
CompileFlags:
  # Forge refreshes the root compile_commands.json link after each build.
  CompilationDatabase: .
  # Clang-only diagnostic flags add nothing to clangd's parse and can produce
  # "unknown argument" warnings when another compiler built the database.
  Remove:
    - -fdiagnostics-color=always
    - -fdiagnostics-color
    - -fcolor-diagnostics
    - -fdiagnostics-show-option
    - -fdiagnostics-show-caret
    - -fdiagnostics-show-labels
    - -fdiagnostics-show-template-tree
    - -fdiagnostics-fixit-info
    - -fcaret-diagnostics-max-lines=0
    - -flto=auto
    - -fno-fat-lto-objects

Index:
  Background: Build
  StandardLibrary: true

Diagnostics:
  MissingIncludes: Strict
  UnusedIncludes: Strict
  ClangTidy:
    Add:
      - bugprone-*
      - performance-*
