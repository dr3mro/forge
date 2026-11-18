# Open verification issues

## Real vcpkg SQLite build needs the source archive

A disposable macOS arm64 project successfully ran `forge add sqlite3 --vcpkg`
and generated the SQLite CMake module. During `forge build`, vcpkg failed to
download `sqlite-autoconf-3540100.tar.gz` for SQLite 3.54.1 because it could
not resolve `sqlite.org`. The real SQLite link and run remain unverified.
Retry the build with the archive in the vcpkg download cache or with network
access to the source host.

The SQLite vcpkg fixture passed. A separate project linked real Conan fmt and
real vcpkg zlib, passed CTest, ran, and rebuilt offline.

## Historical vcpkg fmt build needs registry history

`forge add fmt/12.0.0 --vcpkg` recorded the exact override and vcpkg resolved
it to a port tree. The local shallow checkout lacked that tree, so it could
not build that release. A real `fmt/12.2.1` build using the same feature
passed CTest and ran successfully.
