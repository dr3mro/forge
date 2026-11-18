#!/bin/sh
# Install Forge from a Git repository, or manage a checkout created by this script.
# Keep every operation inside the function so a truncated curl stream cannot run it.
forge_install() (
  set -eu

  # Print an installer error and exit the current operation.
  abort() {
    code=$1
    shift
    printf 'forge: %s\n' "$*" >&2
    exit "$code"
  }

  case ${HOME:-} in
    /*) ;;
    *) abort 2 'HOME must be an absolute path' ;;
  esac
  share="$HOME/.local/share"
  bin="$HOME/.local/bin"
  install="$share/forge"
  link="$bin/forge"
  entry="$install/bin/forge"
  lock="$share/.forge-install-lock"

  step() { printf '[ ] %s\n' "$*" >&2; }
  bash_completion="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/forge"
  zsh_completion="${ZDOTDIR:-$HOME}/.zfunc/_forge"

  mode=${1:-}
  source_mode=git
  source=''
  case $mode in
    --update|--uninstall) [ "$#" -eq 1 ] || abort 2 "unexpected arguments for $mode" ;;
    --source|--repo)
      [ "$#" -eq 2 ] && [ -n "$2" ] || abort 2 "$mode requires a value"
      source=$2
      if [ "$mode" = --source ]; then source_mode=directory; fi ;;
    '')
      if [ -f "$0" ] && [ -f "$(dirname "$0")/lib/_load.sh" ]; then
        source_mode=directory
        source=$(dirname "$0")
      elif [ -n "${FORGE_REPOSITORY:-}" ]; then
        source=$FORGE_REPOSITORY
      else
        abort 2 'usage: sh install.sh [--source DIR | --repo URL]; piped install requires --repo or FORGE_REPOSITORY'
      fi ;;
    -*) abort 2 "unknown option: $mode" ;;
    *) [ "$#" -eq 1 ] || abort 2 'usage: sh install.sh [--source DIR | --repo URL]'; source=$mode ;;
  esac
  if [ "$source_mode" = directory ]; then
    source=$(CDPATH='' cd -- "$source" && pwd -P) || abort 2 'source directory does not exist'
  fi

  step 'Checking installation paths'
  command -v git >/dev/null 2>&1 || abort 3 'Git is required'
  mkdir -p "$share" "$bin" || abort 1 'could not create the install directories'
  mkdir "$lock" || abort 6 "another Forge install operation is active, or $lock exists"

  # Manage only completion links that point to this installation.
  completion() {
    file=$1
    target=$2
    if [ -L "$file" ] && [ "$(readlink "$file")" = "$target" ]; then
      if [ "$mode" = --uninstall ]; then rm "$file"; fi
    elif [ "$mode" != --uninstall ] && [ ! -e "$file" ] && [ ! -L "$file" ]; then
      mkdir -p "${file%/*}" && ln -s "$target" "$file"
    fi
  }

  # Register completions for interactive shells even without a completion framework.
  shell_startup() {
    startup=$1
    loader=$2
    [ ! -L "$startup" ] || return 0
    [ ! -e "$startup" ] || [ -f "$startup" ] || return 0
    if [ "$mode" = --uninstall ]; then
      [ -f "$startup" ] && grep -Fqx -- "$loader" "$startup" || return 0
      tmp=$(mktemp "${startup}.forge.XXXXXX")
      if cp -p "$startup" "$tmp" && awk -v loader="$loader" '$0 != loader' "$startup" > "$tmp"; then
        mv -f "$tmp" "$startup"
      else
        rm -f "$tmp"
        abort 1 "could not remove completion registration from $startup"
      fi
    elif ! { [ -f "$startup" ] && grep -Fqx -- "$loader" "$startup"; }; then
      printf '\n%s\n' "$loader" >> "$startup"
    fi
  }

  shell_completions() {
    completion "$bash_completion" "$install/templates/completions/forge.bash"
    completion "$zsh_completion" "$install/templates/completions/_forge"
    if [ "$mode" = --uninstall ] || [ "$(readlink "$bash_completion" 2>/dev/null || :)" = "$install/templates/completions/forge.bash" ]; then
      shell_startup "$HOME/.bashrc" '[ -r "${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/forge" ] && . "${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/forge" # Forge completion'
    fi
    if [ "$mode" = --uninstall ] || [ "$(readlink "$zsh_completion" 2>/dev/null || :)" = "$install/templates/completions/_forge" ]; then
      shell_startup "${ZDOTDIR:-$HOME}/.zshrc" 'if [[ -r "${ZDOTDIR:-$HOME}/.zfunc/_forge" ]]; then fpath=("${ZDOTDIR:-$HOME}/.zfunc" "${fpath[@]}"); autoload -Uz compinit _forge; (( $+functions[compdef] )) || compinit; compdef _forge forge; fi # Forge completion'
    fi
  }

  # Restore the prior checkout if publishing the staged update fails.
  cleanup() {
    if [ "$committed" -eq 0 ] && [ -d "$lock/previous" ]; then
      if [ ! -e "$install" ] && [ ! -L "$install" ]; then
        mv "$lock/previous" "$install" || return
      else
        printf 'forge: previous installation saved in %s\n' "$lock/previous" >&2
        return
      fi
    fi
    if [ "$committed" -eq 0 ] && [ "$created_link" -eq 1 ] && [ "$(readlink "$link")" = "$entry" ]; then
      rm "$link"
    fi
    rm -rf "$lock"
  }
  committed=0
  created_link=0
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM

  owned_link=0
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$entry" ]; then
      owned_link=1
    else
      abort 6 "refusing to overwrite or unlink $link"
    fi
  fi

  if [ -e "$install" ] || [ -L "$install" ]; then
    [ ! -L "$install" ] && [ -d "$install/.git" ] && [ -f "$install/.git/forge-install" ] \
      || abort 6 "refusing to replace or remove an unmanaged installation at $install"
    changes=$(git -C "$install" status --porcelain --ignored --untracked-files=all) \
      || abort 1 'could not inspect the installed checkout'
    [ -z "$changes" ] || abort 6 "the installed checkout has local changes or extra files: $install"
    case $mode in
      --update)
        if [ -f "$install/.git/forge-source" ]; then
          source_mode=directory
          source=$(cat "$install/.git/forge-source")
        else
          source=$(git -C "$install" remote get-url origin) || abort 4 'installed Git source is unavailable'
        fi ;;
      --uninstall) ;;
      *) abort 6 'Forge is already installed. Run forge update to refresh it.' ;;
    esac
  elif [ "$mode" = --update ]; then
    abort 6 "no Forge installation at $install"
  fi

  if [ "$mode" = --uninstall ]; then
    if [ -d "$install" ]; then
      mv "$install" "$lock/previous" || abort 1 'could not move the installed checkout'
    fi
    if [ "$owned_link" -eq 1 ]; then
      rm "$link" || abort 1 "could not unlink $link"
    fi
    committed=1
    step 'Removing Bash and Zsh completions'
    shell_completions
    printf 'Forge uninstalled.\n'
    exit 0
  fi

  step 'Staging Forge source'
  if [ "$source_mode" = directory ]; then
    mkdir "$lock/incoming"
    for item in bin lib templates install.sh uninstall.sh tools.versions; do
      cp -R "$source/$item" "$lock/incoming/" || abort 4 'could not copy Forge sources'
    done
    git -C "$lock/incoming" init -q
    git -C "$lock/incoming" add -f .
    tree=$(git -C "$lock/incoming" write-tree)
    commit=$(git -C "$lock/incoming" -c user.name=Forge -c user.email=forge@localhost commit-tree "$tree" -m 'Installed Forge source')
    git -C "$lock/incoming" -c core.hooksPath=/dev/null update-ref HEAD "$commit"
    printf '%s\n' "$source" > "$lock/incoming/.git/forge-source"
  else
    git clone --quiet --no-local --depth 1 -- "$source" "$lock/incoming" || abort 4 'could not fetch Forge'
  fi
  [ -x "$lock/incoming/bin/forge" ] && [ -f "$lock/incoming/lib/_load.sh" ] \
    && [ -f "$lock/incoming/install.sh" ] && [ -f "$lock/incoming/uninstall.sh" ] \
    || abort 4 'the repository does not contain an installable Forge checkout'
  : > "$lock/incoming/.git/forge-install"

  step 'Publishing Forge installation'
  if [ "$owned_link" -eq 0 ]; then
    ln -s "$entry" "$link" || abort 6 "could not create $link"
    created_link=1
  fi
  if [ -d "$install" ]; then
    mv "$install" "$lock/previous" || abort 1 'could not move the installed checkout'
  fi
  mv "$lock/incoming" "$install" || abort 1 'could not publish Forge'
  committed=1
  step 'Installing Bash and Zsh completions'
  shell_completions
  printf 'Forge installed at %s\n' "$entry"
  printf 'Add %s to PATH if needed.\n' "$bin"
)

forge_install "$@"
