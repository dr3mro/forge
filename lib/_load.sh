# shellcheck shell=bash
# Forge module loader.
# API: (none — sourcing this file loads all modules).
# Side effects: defines FORGE_LIB and sources modules in dependency order.
# Dependencies: FORGE_HOME must be set by the entry point.
#
# Modules are sourced at TOP LEVEL (not inside a helper function) so that
# `declare -g`-style globals declared in a module keep global scope.

FORGE_LIB="${FORGE_HOME}/lib"
export FORGE_LIB

# shellcheck source=ui.sh
source "${FORGE_LIB}/ui.sh"
# shellcheck source=core.sh
source "${FORGE_LIB}/core.sh"
# shellcheck source=cli-reference.sh
source "${FORGE_LIB}/cli-reference.sh"
# shellcheck source=diagnostics.sh
source "${FORGE_LIB}/diagnostics.sh"
# shellcheck source=manifest.sh
source "${FORGE_LIB}/manifest.sh"
# shellcheck source=workspace.sh
source "${FORGE_LIB}/workspace.sh"
# shellcheck source=state.sh
source "${FORGE_LIB}/state.sh"
# shellcheck source=sync.sh
source "${FORGE_LIB}/sync.sh"
# shellcheck source=cmake.sh
source "${FORGE_LIB}/cmake.sh"
# shellcheck source=vcpkg.sh
source "${FORGE_LIB}/vcpkg.sh"
# shellcheck source=conan.sh
source "${FORGE_LIB}/conan.sh"
# shellcheck source=fetchcontent.sh
source "${FORGE_LIB}/fetchcontent.sh"
# shellcheck source=deps.sh
source "${FORGE_LIB}/deps.sh"
# shellcheck source=project.sh
source "${FORGE_LIB}/project.sh"
# shellcheck source=cli.sh
source "${FORGE_LIB}/cli.sh"

# Command implementations.
for _forge_cmd_file in "${FORGE_LIB}"/commands/*.sh; do
  [[ -e "${_forge_cmd_file}" ]] || continue
  # shellcheck disable=SC1090
  source "${_forge_cmd_file}"
done
unset _forge_cmd_file
