1. [x] Commit all changes since the last commit.

2. [x] Automate package versioning for vcpkg using the Conan-style `pkg/version` format.

   - [x] Accept `forge add fmt/12.0.0 --conan`.
   - [x] Accept `forge add fmt/12.0.0 --vcpkg` and set `build.vcpkg_baseline` automatically.
   - [x] Check for an existing dependency before re-adding it through a package shortcut.

3. [ ] Prompt with `y/N` before syncing and locking after adding a package. Show the user how to do either step later.

4. [ ] Add a watch feature that rebuilds and runs the project when files change.

5. [x] Add Bash and Zsh autocomplete for Git dependencies loaded through CMake FetchContent.

   - [x] Guide users through the repository URL, revision selector, and upstream CMake target.
   - [x] Document a complete example in the README, website, and `forge add --help`.

6. [ ] Commit all changes since the last commit.

7. [ ] also make it if not specified either vcpkg or conan or github then ask the user and if user selected github ask for the info you need to add fecthcontent package, goal to make easy tool and add all these options to the help, how the user would knnow if you don't add to the help

8. [ ] make deps directory like

cmake/deps/fmt.cmake not cmake/deps/fmt/cmakelists.txt

9. [ ] add user.cmake that the user can use to set anything and be safe from changes by you
       and make it have precedence over any other cmake files so the user can override any

10. [ ] also, make it possible for the user to set cmake variable in forge.toml
