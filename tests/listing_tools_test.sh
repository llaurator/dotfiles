#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/bin"
export HOME="$TEST_ROOT/home" TEST_ROOT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Exercise the Debian decision without invoking APT or changing system packages.
(
  source "$ROOT_DIR/scripts/lib.sh"
  source "$ROOT_DIR/scripts/debian.sh"
  PROFILE=server
  TEST_AVAILABLE=''
  TEST_INSTALLED=''
  apt_package_available() { [[ " $TEST_AVAILABLE " == *" $1 "* ]]; }
  command_exists() {
    case "$1" in eza|lsd) [[ " $TEST_INSTALLED " == *" $1 "* ]];; *) command -v "$1" >/dev/null 2>&1;; esac
  }
  run_privileged() {
    printf '%s\n' "$*" >> "$TEST_ROOT/apt.log"
    if [[ "$*" == *' install '* ]]; then
      local package
      for package in "$@"; do
        case "$package" in eza|lsd) TEST_INSTALLED+=" $package";; esac
      done
    fi
  }
  run_tracked_package_transaction() { shift; "$@"; }
  check_case() {
    local available="$1" installed="$2" expected="$3"
    TEST_AVAILABLE="$available" TEST_INSTALLED="$installed"
    : > "$TEST_ROOT/apt.log"
    [[ "$(debian_listing_package)" == "$expected" ]] || fail "selección Debian: $available / $installed"
    install_system_packages > "$TEST_ROOT/install.out"
    grep -Fq 'apt-get install -y git stow zsh jq' "$TEST_ROOT/apt.log" || fail 'faltan paquetes obligatorios'
    if [[ -n "$expected" && " $installed " != *" $expected "* ]]; then
      grep -Fq "apt-get install -y $expected" "$TEST_ROOT/apt.log" || fail "no se instaló $expected"
    fi
    if [[ "$expected" == lsd ]]; then
      if grep -Eq 'install .*eza' "$TEST_ROOT/apt.log"; then fail 'se intentó instalar eza ausente'; fi
    fi
    if [[ -z "$expected" ]]; then
      grep -Fq 'se conservará ls' "$TEST_ROOT/install.out" || fail 'falta aviso de fallback ls'
      if grep -Eq 'install .* (eza|lsd)' "$TEST_ROOT/apt.log"; then fail 'se intentó instalar listado no disponible'; fi
    fi
  }
  check_case 'eza lsd' '' eza
  check_case 'lsd' '' lsd
  check_case '' '' ''
  check_case '' 'lsd' lsd
  check_case 'eza' 'lsd' eza
)

ZSH_BIN="$(command -v zsh)"
BIN="$TEST_ROOT/bin"
ln -s /bin/ls "$BIN/ls"
cat > "$BIN/eza" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_ROOT/eza.log"
for arg do
  case "$arg" in -la|-a|--icons=auto|--group-directories-first|--git|--header|--group|--tree|--level=2|--level=3) ;; *) exit 40;; esac
done
MOCK
cat > "$BIN/lsd" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_ROOT/lsd.log"
for arg do
  case "$arg" in -la|-a|--icon|auto|--group-dirs|first|--git|--header|--blocks|permission,user,group,size,date,name,git|--tree|--depth|2|3) ;; *) exit 40;; esac
done
MOCK
chmod +x "$BIN/eza" "$BIN/lsd"

zsh_aliases() {
  ZSH="$TEST_ROOT/home/.oh-my-zsh" PATH="$BIN" "$ZSH_BIN" -f -c 'source "$1"; alias ls ll la lt lta tree; for alias_name in ls ll la lt lta tree; do eval "$alias_name"; done' -- "$ROOT_DIR/zsh/.config/zsh/common.zsh"
}

zsh_aliases > "$TEST_ROOT/aliases.out" || fail 'aliases eza no funcionan'
grep -Fq "ll='eza -la" "$TEST_ROOT/aliases.out" || fail 'eza no tiene preferencia'
grep -Fq -- '--group' "$TEST_ROOT/eza.log" || fail 'll con eza no muestra grupo'
if [[ -e "$TEST_ROOT/lsd.log" ]]; then fail 'se ejecutó lsd con eza presente'; fi

rm "$BIN/eza"
zsh_aliases > "$TEST_ROOT/aliases.out" || fail 'aliases lsd no funcionan'
grep -Fq "ll='lsd -la" "$TEST_ROOT/aliases.out" || fail 'lsd no es el fallback'
grep -Fq -- '--blocks permission,user,group,size,date,name,git' "$TEST_ROOT/lsd.log" || fail 'll con lsd no muestra propietario y grupo'
if grep -Fq -- '--icons=auto' "$TEST_ROOT/lsd.log"; then fail 'se pasó una flag exclusiva de eza a lsd'; fi

rm "$BIN/lsd"
ZSH="$TEST_ROOT/home/.oh-my-zsh" PATH="$BIN" "$ZSH_BIN" -f -c 'source "$1"; (( $+aliases[ls] == 0 && $+aliases[ll] == 0 )); ls >/dev/null' -- "$ROOT_DIR/zsh/.config/zsh/common.zsh" || fail 'sin eza ni lsd se rompió ls'

printf 'OK: selección Debian y aliases eza, lsd y ls\n'
