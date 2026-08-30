#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  local status=$?
  if (( status != 0 )); then
    find "$TEST_ROOT" -name '*.out' -exec tail -n 30 {} \; >&2 || true
  fi
  rm -rf "$TEST_ROOT"
  return "$status"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

prepare_home() {
  local home="$1" upstream
  for upstream in \
    "$home/.oh-my-zsh" \
    "$home/.oh-my-zsh/custom/themes/powerlevel10k" \
    "$home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "$home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" \
    "$home/.oh-my-zsh/custom/plugins/zsh-history-substring-search"; do
    mkdir -p "$upstream/.git"
  done
}

prepare_repo() {
  local repo="$1" platform_script
  mkdir -p "$repo"
  cp -R "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts" "$ROOT_DIR/zsh" "$ROOT_DIR/git" \
    "$ROOT_DIR/btop" "$ROOT_DIR/ssh" "$ROOT_DIR/vscode" "$repo/"
  for platform_script in macos arch fedora debian; do
    printf '%s\n' '#!/usr/bin/env bash' 'get_system_packages() { SYSTEM_PACKAGES=(); }' \
      'install_system_packages() { :; }' > "$repo/scripts/$platform_script.sh"
  done
}

prepare_common_commands() {
  local bin="$1" command_path command_name
  mkdir -p "$bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/zsh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "forbidden chsh\n" >> "$PLATFORM_FORBIDDEN_LOG"; exit 99' > "$bin/chsh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "forbidden fc-cache\n" >> "$PLATFORM_FORBIDDEN_LOG"; exit 99' > "$bin/fc-cache"
  # Doble mínimo de Stow para crear los enlaces de la instalación fixture.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    'directory= target_root= package=' \
    'for argument in "$@"; do case "$argument" in --dir=*) directory=${argument#--dir=};; --target=*) target_root=${argument#--target=};; --restow|--no-folding) ;; *) package=$argument;; esac; done' \
    'while IFS= read -r -d "" source; do relative=${source#"$directory/$package/"}; target=$target_root/$relative; mkdir -p "${target%/*}"; [[ -e "$target" || -L "$target" ]] || ln -s "$source" "$target"; done < <(find "$directory/$package" -type f -print0)' \
    > "$bin/stow"
  chmod +x "$bin/zsh" "$bin/chsh" "$bin/fc-cache" "$bin/stow"
  for command_name in awk bash cat chmod cksum cmp cp cut date dirname find git grep head jq ln mkdir \
    mktemp mv readlink sed sha256sum sort stat tail tar tr wc xargs; do
    command_path="$(command -v "$command_name")"
    ln -s "$command_path" "$bin/$command_name"
  done
}

run_case() {
  local platform="$1" os_name="$2" manager="$3" expected="$4"
  local case_root="$TEST_ROOT/$platform" home="$TEST_ROOT/$platform/home"
  local repo="$TEST_ROOT/$platform/repo" bin="$TEST_ROOT/$platform/bin"
  local manager_log="$TEST_ROOT/$platform/manager.log" forbidden_log="$TEST_ROOT/$platform/forbidden.log"
  local output="$TEST_ROOT/$platform/dry-run.out" cycle snapshot_before snapshot_after
  mkdir -p "$case_root" "$home"
  prepare_home "$home"
  prepare_repo "$repo"
  prepare_common_commands "$bin"

  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "${1:-}" in -s) printf "%s\n" "$PLATFORM_OS_NAME";; -m) printf "test-arch\n";; *) printf "%s\n" "$PLATFORM_OS_NAME";; esac' \
    > "$bin/uname"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "test-host\n"' > "$bin/hostname"

  case "$platform" in
    arch)
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "pacman %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' '[[ "$1" == -Q && "$2" == -- && "$3" == code ]]' > "$bin/pacman"
      ;;
    fedora)
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "rpm %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' '[[ "$1" == -q && "$2" == -- && "$3" == code ]]' > "$bin/rpm"
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "dnf %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' 'exit 1' > "$bin/dnf"
      ;;
    debian)
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "dpkg-query %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' 'printf "ii \n"' > "$bin/dpkg-query"
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "apt-get %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' '[[ "$1" == -s ]] && printf "Remv code [1]\n"' > "$bin/apt-get"
      ;;
    macos)
      # shellcheck disable=SC2016
      printf '%s\n' '#!/usr/bin/env bash' 'printf "brew %s\n" "$*" >> "$PLATFORM_MANAGER_LOG"' 'case "$1" in list) exit 0;; uses) exit 0;; *) exit 99;; esac' > "$bin/brew"
      ;;
  esac
  chmod +x "$bin/uname" "$bin/hostname"
  case "$platform" in
    arch) chmod +x "$bin/pacman" ;;
    fedora) chmod +x "$bin/rpm" "$bin/dnf" ;;
    debian) chmod +x "$bin/dpkg-query" "$bin/apt-get" ;;
    macos) chmod +x "$bin/brew" ;;
  esac

  HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$bin" \
    PLATFORM_OS_NAME="$os_name" PLATFORM_MANAGER_LOG="$manager_log" PLATFORM_FORBIDDEN_LOG="$forbidden_log" \
    DOTFILES_SKIP_FONT=1 DOTFILES_LOGIN_SHELL="$bin/zsh" GIT_CONFIG_GLOBAL="$home/.gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 "$repo/install.sh" --profile server --yes > "$case_root/install.out" 2>&1
  cycle="$home/.state/dotfiles/cycles/$(< "$home/.state/dotfiles/active")"
  printf 'code\t%s\tinstalled_by_cycle\n' "$manager" >> "$cycle/packages.tsv"
  snapshot_before="$(find "$home" -type f -o -type l | sort | xargs cksum)"
  : > "$manager_log"
  : > "$forbidden_log"

  HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$bin" \
    PLATFORM_OS_NAME="$os_name" PLATFORM_MANAGER_LOG="$manager_log" PLATFORM_FORBIDDEN_LOG="$forbidden_log" \
    DOTFILES_SKIP_FONT=1 DOTFILES_LOGIN_SHELL="$bin/zsh" GIT_CONFIG_GLOBAL="$home/.gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 "$repo/install.sh" --uninstall --dry-run > "$output" 2>&1

  snapshot_after="$(find "$home" -type f -o -type l | sort | xargs cksum)"
  [[ "$snapshot_after" == "$snapshot_before" ]] || fail "$platform: dry-run modificó HOME"
  [[ ! -s "$forbidden_log" ]] || fail "$platform: dry-run ejecutó una operación prohibida"
  grep -Fq "$expected" "$manager_log" || fail "$platform: la plataforma correcta no llegó a la lógica de paquetes"
  grep -Fq 'retirar code' "$output" || fail "$platform: la baseline v2 no planificó code"
  grep -Fq 'Dry-run: no se ha modificado ningún archivo.' "$output" || fail "$platform: faltó confirmación de dry-run"
}

run_case arch Linux pacman 'pacman -Q -- code'
run_case fedora Linux dnf 'rpm -q -- code'
run_case debian Linux apt 'dpkg-query -W'
run_case macos Darwin brew 'brew list --formula code'

printf 'OK: plataforma inicializada en uninstall dry-run para Fedora, Arch, Debian y macOS\n'
