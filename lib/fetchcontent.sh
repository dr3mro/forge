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

# Resolve a tag/branch/HEAD to a full commit SHA via git ls-remote.
fetchcontent_resolve_ref() {
  local url="$1" ref="$2" line sha
  require_tool git
  line=$(git ls-remote "${url}" \
    "refs/tags/${ref}" "refs/tags/${ref}^{}" "refs/heads/${ref}" "${ref}" 2>/dev/null \
    | head -1)
  [[ -n "${line}" ]] \
    || die "${EXIT_DEP}" "could not resolve '${ref}' in ${url}"
  sha="${line%%$'\t'*}"
  [[ "${sha}" =~ ^[0-9a-fA-F]{40}$ ]] \
    || die "${EXIT_DEP}" "'${ref}' did not resolve to a full 40-char SHA"
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
