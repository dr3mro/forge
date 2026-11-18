# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by other modules
# Forge project scaffolding helpers.
# API: forge_render_template; scaffold_project.
# Inputs: FORGE_HOME/templates/base/*; FORGE_ROOT.
# Outputs: a fresh project tree; records generated base files in state.
# Side effects: creates files/directories; refuses to overwrite any of them.

# Substitute template placeholders and print the rendered content.
forge_render_template() {
  local src="$1" kv key val esc
  shift
  local content
  content=$(cat "${src}") || return 1
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    esc="${val//\\/\\\\}"
    esc="${esc//&/\\&}"
    esc="${esc//|/\\|}"
    esc="${esc//\//\\/}"
    content=$(printf '%s\n' "${content}" | sed "s|{{${key}}}|${esc}|g") || return 1
  done
  printf '%s\n' "${content}"
}

# Render one source or header with editable purpose and author fields.
scaffold_source_file() {
  local template="$1" destination="$2" name="$3" author_line="$4" cpp_namespace="${5:-$3}"
  {
    printf '// Author: %s\n//\n// Purpose:\n\n' "${author_line}"
    forge_render_template "${template}" "NAME=${name}" "NAMESPACE=${cpp_namespace}"
  } > "${destination}" || die "${EXIT_OTHER}" "could not write ${destination}"
}

# Read stored attribution, or recover it from older Forge-generated sources.
project_author_line() {
  local author filename first_line
  author=$(mq '.package.author // empty')
  if [[ -n "${author}" ]]; then
    printf '%s' "${author}"
    return
  fi
  for filename in "${FORGE_ROOT}/src/main.cpp" "${FORGE_ROOT}/tests/main.cpp"; do
    if [[ -f "${filename}" ]] && IFS= read -r first_line < "${filename}" \
      && [[ "${first_line}" == '// Author: '* ]]; then
      printf '%s' "${first_line#// Author: }"
      return
    fi
  done
}
# Reject existing files and symlinks before scaffolding.
refuse_file() {
  [[ ! -e "$1" && ! -L "$1" ]] \
    || die "${EXIT_CONFLICT}" "refusing to overwrite: $1"
}

# Write the initial manifest for a binary or library project.
write_manifest() {
  local dir="$1" name="$2" kind="$3" version="$4" description="$5" author_line="$6" extension="$7" linkage="$8" block metadata
  if [[ "${kind}" == "lib" ]]; then
    block=$(cat <<EOF
[[lib]]
name = "${name}"
path = "src/${name}.${extension}"
type = "${linkage:-static}"
links = []

[[test]]
name = "${name}_tests"
path = "tests/main.${extension}"
links = ["${name}"]
EOF
    )
  else
    block=$(cat <<EOF
[[bin]]
name = "${name}"
path = "src/main.cpp"
links = []

[[test]]
name = "${name}_tests"
path = "tests/main.${extension}"
links = []
EOF
    )
  fi
  metadata=$(jq -nr --arg description "${description}" --arg author "${author_line}" '
    {description: $description, author: $author} | to_entries[]
    | select(.value != "") | .key + " = " + (.value | @json | gsub("\u007f"; "\\u007f"))
  ') || return 1
  [[ -z "${metadata}" ]] || metadata+=$'\n'
  cat > "${dir}/Forge.toml" <<EOF
schema = 1

[package]
name = "${name}"
version = "${version}"
${metadata}cppstd = "20"

[build]
generator = "Ninja"
default_profile = "debug"

${block}
EOF
}

# Check C++ namespace syntax and reserved identifiers before creating files.
validate_cpp_namespace() {
  local cpp_namespace="$1" component
  [[ "${cpp_namespace}" =~ ^[A-Za-z][A-Za-z0-9_]*(::[A-Za-z][A-Za-z0-9_]*)*$ ]] \
    || die "${EXIT_USAGE}" "invalid C++ namespace '${cpp_namespace}' (use identifiers separated by ::)"
  local -a components
  read -r -a components <<< "${cpp_namespace//::/ }"
  for component in "${components[@]}"; do
    validate_cpp_identifier "${component}" namespace
  done
}

# Namespace components and class names cannot be C++ keywords.
validate_cpp_identifier() {
  local component="$1" role="$2"
  [[ "${component}" != *__* && "${component}" != _[A-Z]* ]] || die "${EXIT_USAGE}" "reserved C++ ${role} identifier: ${component}"
  case "${component}" in
    alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|char|char8_t|char16_t|char32_t|class|compl|concept|const|const_cast|consteval|constexpr|constinit|continue|co_await|co_return|co_yield|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|private|protected|public|register|reinterpret_cast|requires|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq)
      die "${EXIT_USAGE}" "C++ keyword cannot be used as a ${role}: ${component}" ;;
  esac
}

# Create source files, editor settings, and generated build files.
scaffold_project() {
  local dir="$1" name="$2" kind="$3" git_init="$4" version="${5:-0.1.0}" description="${6:-}"
  local tpl="${FORGE_HOME}/templates/base" author_line="${7:-}" extension="${8:-cpp}" cpp_namespace="${9:-$2}" header=hpp rel linkage="${10:-static}" include_ci="${11:-1}"
  [[ "${extension}" != c ]] || header=h

  [[ ! "${author_line}" =~ [[:cntrl:]] ]] \
    || die "${EXIT_USAGE}" "author attribution must be a single printable line"
  require_tool jq

  # Refuse to overwrite any generated path before writing anything.
  local -a targets=(
    "${dir}/Forge.toml" "${dir}/CMakeLists.txt" "${dir}/CMakePresets.json"
    "${dir}/.gitignore" "${dir}/README.md"
    "${dir}/tests/main.${extension}" "${dir}/version.cpp.in" "${dir}/forge-reference-transaction"
  )
  while IFS= read -r rel; do
    if [[ "${rel}" != conanfile.txt ]]; then targets+=("${dir}/${rel}"); fi
  done < <(cmake_managed_files)
  if [[ "${kind}" == "lib" ]]; then
    targets+=("${dir}/src/${name}.${extension}" "${dir}/include/${name}.${header}"
      "${dir}/include/${name}_export.h")
  else
    targets+=("${dir}/src/main.cpp")
  fi
  [[ ! -L "${dir}/cmake" && ! -L "${dir}/.forge" ]] \
    || die "${EXIT_CONFLICT}" "refusing to scaffold through a symlinked cmake or .forge directory"
  local editor
  for editor in .zed .vscode; do
    if [[ -e "${dir}/${editor}" || -L "${dir}/${editor}" ]]; then
      [[ -d "${dir}/${editor}" && ! -L "${dir}/${editor}" ]] \
        || die "${EXIT_CONFLICT}" "refusing to use an unsafe editor directory: ${dir}/${editor}"
    fi
    targets+=("${dir}/${editor}/tasks.json")
  done
  targets+=("${dir}/.zed/debug.json" "${dir}/.vscode/launch.json")
  if (( include_ci )); then
    workflow_check_destinations "${dir}"
  fi
  local t
  for t in "${targets[@]}"; do refuse_file "${t}"; done

  progress "Creating project directories"
  mkdir -p "${dir}/src" "${dir}/tests" "${dir}/include" "${dir}/cmake" \
    "${dir}/.forge" "${dir}/target" "${dir}/.zed" "${dir}/.vscode" \
    || die "${EXIT_OTHER}" "could not create project directories"

  progress_finish

  progress "Writing editor settings"
  # Libraries launch their test executable in LLDB.
  local debug_target="${name}"
  if [[ "${kind}" == lib ]]; then
    debug_target="${name}_tests"
  fi
  local config
  for config in .zed/tasks.json .zed/debug.json .vscode/tasks.json .vscode/launch.json; do
    forge_render_template "${FORGE_HOME}/templates/editors/${config#.}.tpl" \
      "DEBUG_TARGET=${debug_target}" > "${dir}/${config}" \
      || die "${EXIT_OTHER}" "could not write ${config}"
  done

  progress_finish

  progress "Writing Forge.toml"
  write_manifest "${dir}" "${name}" "${kind}" "${version}" "${description}" "${author_line}" "${extension}" "${linkage}" \
    || die "${EXIT_OTHER}" "could not write Forge.toml"

  progress_finish

  progress "Writing project sources and version template"
  cp "${tpl}/version.cpp.in.tpl" "${dir}/version.cpp.in" \
    || die "${EXIT_OTHER}" "could not write version.cpp.in"
  cp "${tpl}/reference-transaction.tpl" "${dir}/forge-reference-transaction" \
    && chmod +x "${dir}/forge-reference-transaction" \
    || die "${EXIT_OTHER}" "could not write forge-reference-transaction"
  if [[ "${kind}" == "lib" ]]; then
    scaffold_source_file "${tpl}/lib.${extension}.tpl" "${dir}/src/${name}.${extension}" "${name}" "${author_line}" "${cpp_namespace}"
    scaffold_source_file "${tpl}/lib_export.h.tpl" "${dir}/include/${name}_export.h" "${name}" "${author_line}"
    scaffold_source_file "${tpl}/lib.${header}.tpl" "${dir}/include/${name}.${header}" "${name}" "${author_line}" "${cpp_namespace}"
    scaffold_source_file "${tpl}/tests_lib.${extension}.tpl" "${dir}/tests/main.${extension}" "${name}" "${author_line}" "${cpp_namespace}"
  else
    scaffold_source_file "${tpl}/main.cpp.tpl" "${dir}/src/main.cpp" "${name}" "${author_line}"
    scaffold_source_file "${tpl}/tests_main.cpp.tpl" "${dir}/tests/main.${extension}" "${name}" "${author_line}"
  fi

  progress_finish

  progress "Writing project documentation and ignore rules"
  forge_render_template "${tpl}/.gitignore.tpl" > "${dir}/.gitignore" \
    || die "${EXIT_OTHER}" "could not write .gitignore"
  forge_render_template "${tpl}/README.md.tpl" "NAME=${name}" > "${dir}/README.md" \
    || die "${EXIT_OTHER}" "could not write README.md"

  if [[ -n "${description}" ]]; then
    printf '\n## Description\n\n%s\n' "${description}" >> "${dir}/README.md" \
      || die "${EXIT_OTHER}" "could not add the project description to README.md"
  fi

  progress_finish

  FORGE_ROOT="${dir}"
  FORGE_MANIFEST_PATH="${dir}/Forge.toml"
  manifest_load
  progress "Generating CMake files and recording sync state"
  mkdir -p "${dir}/cmake" || die "${EXIT_OTHER}" "could not create the cmake directory"
  if [[ ! -e "${dir}/cmake/user.cmake" && ! -L "${dir}/cmake/user.cmake" ]]; then
    (set -o noclobber; printf '# Set local CMake overrides here. Forge sync preserves this file.\n' > "${dir}/cmake/user.cmake") \
      || die "${EXIT_OTHER}" "could not create cmake/user.cmake"
  fi
  cmake_render_all "${dir}" && state_init && state_record_generated \
    || die "${EXIT_OTHER}" "could not generate CMake files or record sync state"
  progress_finish
  if (( include_ci )); then workflow_write "${dir}"; fi

  if (( git_init )); then
    progress "Initializing Git repository"
    require_tool git
    (cd "${dir}" && git init -q) \
      || die "${EXIT_OTHER}" "git init failed in ${dir}"
    progress_finish
  fi
  if [[ -e "${dir}/.git" ]]; then
    scaffold_version_hook "${dir}"
  fi
}

# Install into the default hooks directory when the repository has no competing hook.
scaffold_version_hook() {
  local dir="$1" hooks
  if git -C "${dir}" config --get core.hooksPath >/dev/null; then
    warn "custom Git hooks path configured; add forge-reference-transaction to your hooks"
    return
  fi
  hooks=$(git -C "${dir}" rev-parse --path-format=absolute --git-path hooks) \
    || die "${EXIT_OTHER}" "could not locate Git hooks"
  if [[ -e "${hooks}/reference-transaction" || -L "${hooks}/reference-transaction" ]]; then
    warn "existing reference-transaction hook; invoke forge-reference-transaction from it to enable tag versions"
    return
  fi
  progress "Installing Git tag version hook"
  mkdir -p "${hooks}" \
    || die "${EXIT_OTHER}" "could not create Git hooks directory"
  (set -o noclobber; cat "${dir}/forge-reference-transaction" > "${hooks}/reference-transaction") \
    && chmod +x "${hooks}/reference-transaction" \
    || die "${EXIT_OTHER}" "could not install Git tag version hook"
  progress_finish
}
