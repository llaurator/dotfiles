#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$HOME" "$FAKE_BIN" "$TEST_ROOT/cycle"
PATH="$FAKE_BIN:$PATH"
export HOME PATH

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

BASELINE_MODE=active
BASELINE_FORMAT=2
DOTFILES_DISTRO=debian
DOTFILES_ROOT="$ROOT_DIR"
DOTFILES_LOGIN_SHELL=/bin/bash
ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "$1" == -W ]] && { printf "ii "; exit 0; }' \
  'exit 1' > "$FAKE_BIN/dpkg-query"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "$1" == --print-architecture ]] && { printf "amd64\n"; exit 0; }' \
  'exit 1' > "$FAKE_BIN/dpkg"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'cat "$HOME/apt-plan.txt"' > "$FAKE_BIN/apt-get"
chmod +x "$FAKE_BIN/dpkg-query" "$FAKE_BIN/dpkg" "$FAKE_BIN/apt-get"

reset_case() {
  printf 'package\tmanager\tstate\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
  rm -f -- "$ACTIVE_CYCLE_DIR/restore-journal.tsv" "$ACTIVE_CYCLE_DIR/restore.log"
  : > "$HOME/apt-plan.txt"
}

set_registered() {
  local package
  for package in "$@"; do printf '%s\tapt\tinstalled_by_cycle\n' "$package" >> "$ACTIVE_CYCLE_DIR/packages.tsv"; done
}

set_plan() { printf 'Remv %s [1.0]\n' "$@" > "$HOME/apt-plan.txt"; }

# A/B/E/F: APT puede omitir el sufijo de una única arquitectura, pero las
# coincidencias exactas y los nombres sin arquitectura conservan su semántica.
reset_case; set_registered libjq1:arm64; set_plan libjq1
preflight_package_removal || fail 'libjq1:arm64 no se reconcilió con libjq1'
reset_case; set_registered libjq1:amd64; set_plan libjq1
preflight_package_removal || fail 'libjq1:amd64 no se reconcilió con libjq1'
reset_case; set_registered libjq1:arm64; set_plan libjq1:arm64
preflight_package_removal || fail 'la coincidencia APT exacta falló'
reset_case; set_registered libjq1; set_plan libjq1:amd64
preflight_package_removal || fail 'libjq1 no se reconcilió con su arquitectura nativa'
reset_case; set_registered zsh stow; set_plan zsh stow
preflight_package_removal || fail 'los nombres APT sin arquitectura cambiaron de comportamiento'

# C: dos arquitecturas para el mismo basename son ambiguas; no se adivina.
reset_case; set_registered libjq1:amd64 libjq1:i386; set_plan libjq1
if (preflight_package_removal); then fail 'multiarch ambiguo fue aceptado'; fi

# D: cualquier elemento ajeno del plan mantiene el abort conservador.
reset_case; set_registered libjq1:arm64; set_plan libjq1 foreign-package
if (preflight_package_removal); then fail 'un paquete ajeno del plan fue aceptado'; fi

printf 'OK: reconciliación conservadora de identidades APT con arquitectura\n'
