# Manifest reference (`Forge.toml`)

Real TOML 1.0. `schema = 1` is required for ordinary projects; `schema = 2`
adds `[workspace]`. Unknown keys, unsafe names and paths are rejected before
any command acts on the file.

```toml
schema = 1

[package]
name = "hello"
version = "0.1.0"
description = "Example application" # optional, used by forge docs
author = "A. Developer <dev@example.test>" # optional source attribution
cppstd = "20"            # 17, 20 or 23

[build]
generator = "Ninja"      # Ninja, Unix Makefiles (Make accepted as alias)
default_profile = "debug"

[[bin]]
name = "hello"
path = "src/main.cpp"
links = ["fmt", "logger"]

[[lib]]
name = "hello_lib"
type = "static"
path = "src/hello.cpp"
links = []

[[test]]
name = "hello_tests"
path = "tests/main.cpp"
links = ["hello_lib", "catch2"]

[dependencies.fmt]
source = "conan"
ref = "fmt/12.1.0"
cmake_target = "fmt::fmt-header-only"
conan_options = { header_only = "True" }

[dependencies.zlib]
source = "vcpkg"
port = "zlib"
cmake_package = "ZLIB"
cmake_target = "ZLIB::ZLIB"

[dependencies.catch2]
source = "git"
url = "https://github.com/catchorg/Catch2.git"
rev = "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"
cmake_target = "Catch2::Catch2WithMain"

[dependencies.logger]
source = "path"
path = "libs/logger"
cmake_target = "logger"
```

## Rules

- Every dependency states its source: `conan`, `git` or `path`. Each source
  accepts only its own fields. `conan_options` is an optional table of strings
  (rendered as `ref/*:option=value` lines in `conanfile.txt`).
- Git `rev` must be a full 40-character SHA. Tags and branches are resolved
  once with `forge deps pin NAME --tag TAG` and written into the manifest.
- Git `url` must use `https://`, `git@` or `file://`; shell metacharacters are
  rejected. Names match `^[A-Za-z_][A-Za-z0-9_]*$`; paths are relative and may
  not contain `..`, backslashes or shell metacharacters.
- `links` on a target may name a dependency key (mapped to its `cmake_target`)
  or another target. When `links` is omitted, the documented default is: link
  all declared dependencies; test targets additionally link all libraries.
- Duplicate dependency names are impossible (keyed tables). Duplicate
  `cmake_target` values, duplicate Conan refs and dependency/target name
  collisions are diagnosed by `deps status` / `add`.
- Examples use verified values: with Conan's `fmt/12.1.0` and
  `header_only=True`, the provided CMake target is `fmt::fmt-header-only`,
  not `fmt::fmt`.

Library targets accept optional `type = "static"` or `type = "shared"`.
New library scaffolds record `static` unless you request a shared library.
When `type` is omitted, CMake determines linkage through `BUILD_SHARED_LIBS`.
After editing a library type, run `forge sync --apply --yes`.

## Workspaces (schema 2)

```toml
schema = 2
[workspace]
members = ["libs/foo", "bins/bar"]
```

Members are full Forge projects with their own `Forge.toml`, dependencies and
CMake files. They are added with `forge generate lib|bin NAME` and included via
`add_subdirectory`. A member can itself declare `[workspace] members`, so the
project graph is recursive: `libs/lib1/libs/lib2` is discovered automatically.
Every target in the reachable graph is available to any project's `links` by
name. Because paths may not contain `..`, members can only point to descendants
(the graph is a tree). `forge generate lib NAME` also appends `NAME` to the
`links` of every target in the current project, so the new library is usable
immediately after `forge sync --apply`.

## Editing

`add` appends one keyed table; `remove` deletes exactly that block. Both back
up the file, reparse and validate the result, then replace it atomically.
Comments and formatting outside the block are preserved. Any edit that cannot
be placed unambiguously is refused. See `docs/decisions/0002-manifest-editing.md`.
