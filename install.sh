#!/bin/sh
# Install Forge from a Git repository or local source directory.
# Keep every operation inside the function so a truncated curl stream cannot run it.
forge_install() (
  set -eu

  # Print an installer error and exit the current operation.
  abort() {
    code=$1
    shift
    step_finish "$code"
    printf 'forge: %s\n' "$*" >&2
    exit "$code"
  }

  current_step=''
  step() { current_step=$*; }

  step_finish() {
    [ -n "$current_step" ] || return 0
    if [ "${1:-0}" -eq 0 ]; then
      mark='✓' color=32
    else
      mark='✗' color=31
    fi
    if [ -z "${NO_COLOR+x}" ] && { [ "${FORCE_COLOR:-0}" = 1 ] || [ -t 2 ]; }; then
      printf '[\033[%sm%s\033[0m] %s\n' "$color" "$mark" "$current_step" >&2
    else
      printf '[%s] %s\n' "$mark" "$current_step" >&2
    fi
    current_step=''
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

  bash_completion="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/forge"
  zsh_completion="${ZDOTDIR:-$HOME}/.zfunc/_forge"

  mode=${1:-}
  source_mode=git
  source=https://github.com/dr3mro/forge.git
  usage='usage: sh install.sh [--source DIR_OR_REPO | --repo REPO]'
  case $mode in
    --update|--uninstall) [ "$#" -eq 1 ] || abort 2 "unexpected arguments for $mode" ;;
    --source|--repo)
      [ "$#" -eq 2 ] && [ -n "$2" ] || abort 2 "$mode requires a value"
      source=$2
      if [ "$mode" = --source ] && [ -d "$source" ]; then
        source_mode=directory
      fi ;;
    '') [ "$#" -eq 0 ] || abort 2 "$usage" ;;
    -*) abort 2 "unknown option: $mode" ;;
    *) [ "$#" -eq 1 ] || abort 2 "$usage"; source=$mode ;;
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

  # Add or remove one exact startup line, preserving unrelated shell settings.
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
        abort 1 "could not remove Forge registration from $startup"
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

  shell_path() {
    path_loader='case ":${PATH:-}:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;; esac # Forge PATH'
    shell_startup "$HOME/.bashrc" "$path_loader"
    shell_startup "${ZDOTDIR:-$HOME}/.zshrc" "$path_loader"
    if [ "$mode" = --uninstall ]; then
      for profile in .bash_profile .bash_login .profile; do
        shell_startup "$HOME/$profile" "$path_loader"
      done
    else
      # Bash login shells read only the first available login profile.
      for profile in .bash_profile .bash_login .profile; do
        if [ -e "$HOME/$profile" ] || [ -L "$HOME/$profile" ]; then
          shell_startup "$HOME/$profile" "$path_loader"
          return
        fi
      done
      shell_startup "$HOME/.bash_profile" "$path_loader"
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
  trap 'step_finish "$?"; cleanup' EXIT
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

  # Report a current installation. Return 1 when the user asks to reinstall.
  report_current() {
    step_finish
    printf 'Forge is already up to date (v%s).\n' "$1"
    if [ -t 0 ]; then
      printf 'Reinstall anyway? [y/N] '
      IFS= read -r answer || answer=
      case $answer in
        y|Y|yes|YES|Yes) return 1 ;;
      esac
    fi
    return 0
  }

  if [ "$mode" = --update ]; then
    step 'Checking the latest Forge release'
    if [ -f "$install/.git/forge-version" ]; then
      installed_version=$(cat "$install/.git/forge-version")
    else
      installed_version=$(awk -F'"' '/^FORGE_VERSION=/{print $2; exit}' "$install/bin/forge")
    fi
    latest_tag=''
    current=no
    if [ "$source_mode" = directory ]; then
      # Local sources have no remote tag: an unchanged tree is already current.
      same=yes
      for item in bin lib templates install.sh uninstall.sh tools.versions LICENSE; do
        if [ -e "$source/$item" ] || [ -d "$source/$item" ]; then
          if [ ! -e "$install/$item" ] || ! diff -r -q "$source/$item" "$install/$item" >/dev/null 2>&1; then
            same=no
          fi
        elif [ -e "$install/$item" ]; then
          same=no
        fi
      done
      if [ "$same" = yes ]; then current=yes; fi
    else
      installed_head=$(git -C "$install" rev-parse HEAD 2>/dev/null || :)
      latest_tag=$(
        git ls-remote --tags --refs "$source" 2>/dev/null \
          | awk '{ sub(/^refs\/tags\//, "", $2); print $2 }' \
          | sed 's/^v//' \
          | grep -E '^[0-9]+([.][0-9]+)*$' \
          | sort -V \
          | tail -n 1 || :
      )
      if [ -n "$latest_tag" ]; then
        if [ "$latest_tag" = "$installed_version" ]; then current=yes; fi
      elif [ -n "$installed_head" ]; then
        remote_head=$(git ls-remote "$source" HEAD 2>/dev/null | awk 'NR == 1 {print $1}' || :)
        if [ -n "$remote_head" ] && [ "$remote_head" = "$installed_head" ]; then current=yes; fi
      fi
    fi
    if [ "$current" = yes ]; then
      report_current "${latest_tag:-$installed_version}" && exit 0
    fi
    step_finish
  fi

  step_finish
  if [ "$mode" = --uninstall ]; then
    step 'Removing Forge installation'
    if [ -d "$install" ]; then
      mv "$install" "$lock/previous" || abort 1 'could not move the installed checkout'
    fi
    if [ "$owned_link" -eq 1 ]; then
      rm "$link" || abort 1 "could not unlink $link"
    fi
    committed=1
    step_finish
    step 'Removing Bash and Zsh PATH and completion entries'
    shell_completions
    shell_path
    step_finish
    printf 'Forge uninstalled.\n'
    exit 0
  fi

  step 'Staging Forge source'
  if [ "$source_mode" = directory ]; then
    mkdir "$lock/incoming"
    for item in bin lib templates install.sh uninstall.sh tools.versions; do
      cp -R "$source/$item" "$lock/incoming/" || abort 4 'could not copy Forge sources'
    done
    if [ -f "$source/LICENSE" ]; then
      cp "$source/LICENSE" "$lock/incoming/" || abort 4 'could not copy the source license'
    fi
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
  awk -F'"' '/^FORGE_VERSION=/{print $2; exit}' "$lock/incoming/bin/forge" > "$lock/incoming/.git/forge-version"
  step_finish

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
  step_finish
  step 'Configuring Bash and Zsh PATH and completions'
  shell_completions
  shell_path
  step_finish
  printf 'Forge installed at %s\n' "$entry"
  printf 'Start a new shell to load PATH and shell completions.\n'
)

forge_install "$@"
