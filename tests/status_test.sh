#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { command grep -Fq -- "$2" "$1" || fail "no se encontró '$2' en $1"; }

HOME="$TEST_ROOT/home"
XDG_STATE_HOME="$HOME/.state"
DOTFILES_ROOT="$ROOT_DIR"
GIT_CONFIG_NOSYSTEM=1
export HOME XDG_STATE_HOME DOTFILES_ROOT GIT_CONFIG_NOSYSTEM
mkdir -p "$HOME/.state/dotfiles/cycles/20260831T000000Z-1"
cycle="$HOME/.state/dotfiles/cycles/20260831T000000Z-1"

printf '20260831T000000Z-1\n' > "$HOME/.state/dotfiles/active"
printf '%s\n' \
  $'format_version\t1' \
  $'installation_id\t20260831T000000Z-1' \
  $'home\t'"$HOME" \
  $'repo\t'"$DOTFILES_ROOT" \
  $'profile\tpersonal' \
  $'commit\ttest' \
  $'created_at\ttest' > "$cycle/metadata.tsv"
printf 'active\n' > "$cycle/status"
printf '%s\n' \
  $'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint' \
  $'.config/dotfiles/zsh-components.zsh\tmissing\t-\t-\tzsh_components\t-\t-' > "$cycle/manifest.tsv"
printf '%s\n' \
  $'relative_path\tkind\tproof\tsource' \
  $'.config/dotfiles/zsh-components.zsh\tzsh_components\tfile:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:0:644\t-' \
  > "$cycle/ownership.tsv"

state_before="$(find "$HOME/.state" -type f -exec cksum {} + | sort)"
show_dotfiles_status > "$TEST_ROOT/status.out"

assert_contains "$TEST_ROOT/status.out" 'Installed:  no'
assert_contains "$TEST_ROOT/status.out" 'Managed resources:'
assert_contains "$TEST_ROOT/status.out" '~/.config/dotfiles/zsh-components.zsh (ausente)'
[[ ! -e "$HOME/.config/dotfiles/zsh-components.zsh" ]] || fail 'status reparó un recurso gestionado ausente'
[[ "$(find "$HOME/.state" -type f -exec cksum {} + | sort)" == "$state_before" ]] ||
  fail 'status modificó la baseline al comprobar recursos gestionados'

printf 'OK: status detecta recursos gestionados ausentes sin modificar el estado\n'
