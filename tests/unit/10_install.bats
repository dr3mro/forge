#!/usr/bin/env bats
# Exercise per-user installation against a temporary Git source and home.
load ../test_helper

# Create an independent source so update can fetch a new commit without network access.
setup() {
  SOURCE="${BATS_TEST_TMPDIR}/source"
  export HOME="${BATS_TEST_TMPDIR}/test home"
  mkdir -p "$HOME" "$SOURCE"
  cp -R "${FORGE_PROJECT_DIR}/bin" "${FORGE_PROJECT_DIR}/lib" "${FORGE_PROJECT_DIR}/templates" "$SOURCE"
  cp "${FORGE_PROJECT_DIR}"/{install.sh,uninstall.sh,tools.versions} "$SOURCE"
  git -C "$SOURCE" init -q
  git -C "$SOURCE" config user.name 'Forge Tests'
  git -C "$SOURCE" config user.email 'forge@example.invalid'
  git -C "$SOURCE" add .
  git -C "$SOURCE" commit -qm initial
  LAUNCHER="$HOME/.local/bin/forge"
  INSTALLATION="$HOME/.local/share/forge"
}

@test "piped installer, CLI update, and CLI uninstall work through the launcher" {
  run sh -s -- "file://$SOURCE" < "$SOURCE/install.sh"
  [ "$status" -eq 0 ]
  [ "$(readlink "$LAUNCHER")" = "$INSTALLATION/bin/forge" ]

  run "$LAUNCHER" version
  [ "$status" -eq 0 ]
  [ "$output" = "forge 0.1.0" ]
  local initial
  initial=$(git -C "$INSTALLATION" rev-parse HEAD)

  git -C "$SOURCE" commit -qm update --allow-empty
  run "$LAUNCHER" update --dry-run
  [ "$status" -eq 0 ]
  [ "$(git -C "$INSTALLATION" rev-parse HEAD)" = "$initial" ]

  run "$LAUNCHER" update
  [ "$status" -eq 0 ]
  [ "$(git -C "$INSTALLATION" rev-parse HEAD)" = "$(git -C "$SOURCE" rev-parse HEAD)" ]

  run "$LAUNCHER" uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$INSTALLATION" ]
  [ ! -L "$LAUNCHER" ]
}

@test "installer preserves an unrelated launcher and an installation with extra files" {
  mkdir -p "${LAUNCHER%/*}"
  printf 'user data\n' > "$LAUNCHER"
  run sh "$SOURCE/install.sh" "file://$SOURCE"
  [ "$status" -eq 6 ]
  [ "$(cat "$LAUNCHER")" = "user data" ]
  [ ! -e "$INSTALLATION" ]
  rm "$LAUNCHER"

  run sh "$SOURCE/install.sh" "file://$SOURCE"
  [ "$status" -eq 0 ]
  touch "$INSTALLATION/local-notes"
  run "$LAUNCHER" update
  [ "$status" -eq 6 ]
  cd "$SOURCE"
  run sh uninstall.sh
  [ "$status" -eq 6 ]
  [ -f "$INSTALLATION/local-notes" ]
  [ -L "$LAUNCHER" ]
}

@test "local checkout install and standalone uninstall work with relative script paths" {
  cd "$SOURCE"
  run sh install.sh "$PWD"
  [ "$status" -eq 0 ]
  [ "$(git -C "$INSTALLATION" rev-parse --is-shallow-repository)" = true ]
  run sh uninstall.sh
  [ "$status" -eq 0 ]
  [ ! -e "$INSTALLATION" ]
  [ ! -L "$LAUNCHER" ]
}

@test "offline and failed updates preserve the installed checkout and launcher" {
  run sh "$SOURCE/install.sh" "file://$SOURCE"
  [ "$status" -eq 0 ]
  local initial
  initial=$(git -C "$INSTALLATION" rev-parse HEAD)
  mv "$SOURCE" "$SOURCE.moved"

  run "$LAUNCHER" --offline update
  [ "$status" -eq 4 ]
  [[ "$output" == *"requires a connection"* ]]
  run "$LAUNCHER" update
  [ "$status" -eq 4 ]
  [[ "$output" == *"could not fetch Forge"* ]]
  [ "$(git -C "$INSTALLATION" rev-parse HEAD)" = "$initial" ]
  [ "$(readlink "$LAUNCHER")" = "$INSTALLATION/bin/forge" ]
  [ ! -e "$HOME/.local/share/.forge-install-lock" ]
}

@test "source-directory install copies current files and manages both completions" {
  cd "$SOURCE"
  printf '# user bash settings\n' > "$HOME/.bashrc"
  printf '# user zsh settings\n' > "$HOME/.zshrc"
  run sh install.sh
  [ "$status" -eq 0 ]
  local bash_completion="$HOME/.local/share/bash-completion/completions/forge"
  local zsh_completion="$HOME/.zfunc/_forge"
  [ -f "$bash_completion" ]
  [ -f "$zsh_completion" ]
  run bash --noprofile -c '. "$HOME/.bashrc"; complete -p forge'
  [ "$status" -eq 0 ]
  if command -v zsh >/dev/null 2>&1; then
    run zsh -c '. "$HOME/.zshrc"; [[ ${_comps[forge]} == _forge ]]'
    [ "$status" -eq 0 ]
  fi

  printf '# uncommitted change\n' >> lib/ui.sh
  run "$LAUNCHER" --offline update
  [ "$status" -eq 0 ]
  grep -Fxq '# uncommitted change' "$INSTALLATION/lib/ui.sh"
  [ "$(grep -c 'Forge completion' "$HOME/.bashrc")" -eq 1 ]

  run sh uninstall.sh
  [ "$status" -eq 0 ]
  [ ! -L "$bash_completion" ]
  [ ! -L "$zsh_completion" ]
  ! grep -q 'Forge completion' "$HOME/.bashrc" "$HOME/.zshrc"
  grep -Fxq '# user bash settings' "$HOME/.bashrc"
  grep -Fxq '# user zsh settings' "$HOME/.zshrc"
}

@test "piped installer requires a repository and preserves user completion files" {
  run sh -s < "$SOURCE/install.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires --repo or FORGE_REPOSITORY"* ]]
  mkdir -p "$HOME/.zfunc"
  printf 'user completion\n' > "$HOME/.zfunc/_forge"
  run sh -s -- --repo "file://$SOURCE" < "$SOURCE/install.sh"
  [ "$status" -eq 0 ]
  run "$LAUNCHER" uninstall
  [ "$status" -eq 0 ]
  grep -Fxq 'user completion' "$HOME/.zfunc/_forge"
}

@test "installed Bash and Zsh completions use the same scoped command catalog" {
  run sh "$SOURCE/install.sh" --source "$SOURCE"
  [ "$status" -eq 0 ]
  export PATH="${LAUNCHER%/*}:$PATH"
  run /bin/bash --noprofile -c '
    . "$HOME/.bashrc"
    COMP_WORDS=(forge deps pin upstream --br)
    COMP_CWORD=4
    _forge_complete
    printf "%s\n" "${COMPREPLY[@]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = '--branch' ]
  if command -v zsh >/dev/null; then
    run zsh -fc '
      words=(forge deps status --form)
      CURRENT=4 PREFIX=--form
      compadd() { printf "%s\n" "$@"; }
      source "$HOME/.zfunc/_forge"
    '
    [ "$status" -eq 0 ]
    [ "$output" = $'--\n--format' ]
  fi
}
