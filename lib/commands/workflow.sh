# shellcheck shell=bash
# Generate user-owned GitHub Actions and CI support files.

workflow_files() {
  printf '%s\n' .github/workflows/forge.yml .github/forge/ci.py \
    .github/forge/Dockerfile .github/forge/Dockerfile.dockerignore
}

workflow_check_destinations() {
  local root="$1" path
  for path in .github .github/workflows .github/forge; do
    [[ ! -L "${root}/${path}" && ( ! -e "${root}/${path}" || -d "${root}/${path}" ) ]] \
      || die "${EXIT_CONFLICT}" "refusing to write through ${root}/${path}"
  done
  while IFS= read -r path; do refuse_file "${root}/${path}"; done < <(workflow_files)
}

workflow_write() {
  local root="$1" path
  progress "Writing GitHub Actions workflow"
  mkdir -p "${root}/.github/workflows" "${root}/.github/forge" \
    || die "${EXIT_OTHER}" "could not create GitHub Actions directories"
  while IFS= read -r path; do
    (set -o noclobber; cat "${FORGE_HOME}/templates/workflow/${path##*/}.tpl" > "${root}/${path}") \
      || die "${EXIT_OTHER}" "could not write ${path}"
  done < <(workflow_files)
  progress_finish
}

cmd_workflow() {
  [[ $# -eq 1 && "$1" == init ]] || die "${EXIT_USAGE}" "usage: forge workflow init"
  require_project
  workflow_check_destinations "${FORGE_ROOT}"
  if (( FORGE_DRY_RUN )); then
    status "dry-run: would create .github/workflows/forge.yml and CI support files"
    return
  fi
  workflow_write "${FORGE_ROOT}"
  out "created .github/workflows/forge.yml and CI support files (user-owned)"
}
