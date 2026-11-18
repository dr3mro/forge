# shellcheck shell=bash
# shellcheck disable=SC2034  # globals consumed by other modules
# Forge FetchContent / Git-source helpers.
# API: fetchcontent_has_deps fetchcontent_resolve_ref fetchcontent_sources_populated
# Inputs: FORGE_MANIFEST_JSON, FORGE_ROOT, git.
# Outputs: resolved SHAs on stdout. Side effects: only read-only git queries.

# Report whether the current manifest declares Git dependencies.
fetchcontent_has_deps() {
  (( $(mq '[((.dependencies // {}) | to_entries[] | select(.value.source == "git"))] | length') > 0 ))
}

# Resolve an exact branch or tag, preferring the commit peeled from an annotated tag.
fetchcontent_resolve_ref() {
  local url="$1" selector="$2" ref="$3" full_ref rows sha remote_ref exact="" peeled=""
  local -a refs=()
  case "${selector}" in
    --tag) full_ref="refs/tags/${ref}"; refs=("${full_ref}" "${full_ref}^{}") ;;
    --branch) full_ref="refs/heads/${ref}"; refs=("${full_ref}") ;;
  esac

  require_tool git
  rows=$(git ls-remote -- "${url}" "${refs[@]}" 2>/dev/null) \
    || die "${EXIT_DEP}" "could not resolve '${ref}' in ${url}"
  while IFS=$'\t' read -r sha remote_ref; do
    case "${remote_ref}" in
      "${full_ref}") exact="${sha}" ;;
      "${full_ref}^{}") peeled="${sha}" ;;
    esac
  done <<< "${rows}"
  sha="${peeled:-${exact}}"
  [[ "${sha}" =~ ^[0-9a-fA-F]{40}$ ]] \
    || die "${EXIT_DEP}" "could not resolve '${ref}' to a full 40-char SHA in ${url}"
  printf '%s' "${sha}"
}

# Check whether a Git source is already populated in a build tree.
fetchcontent_sources_populated() {
  local build_dir="$1" key count=0
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    [[ -d "${build_dir}/_deps/${key}-src" ]] && count=$((count + 1))
  done < <(mq '((.dependencies // {}) | to_entries[] | select(.value.source == "git") | .key)')
  local total
  total=$(mq '[((.dependencies // {}) | to_entries[] | select(.value.source == "git"))] | length')
  (( total > 0 && count == total ))
}
