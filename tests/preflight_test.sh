#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
mkdir -p "$HOME/.oh-my-zsh/.git" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git"
export HOME

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
get_system_packages() { SYSTEM_PACKAGES=(git stow grc); }
package_is_installed() { [[ "$1" == git || "$1" == stow ]]; }
BACKUP_CONFLICTS=0
CONFLICT_RELS=(.zshrc)

before="$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
print_install_preflight personal > "$TEST_ROOT/preflight.out"
after="$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
[[ "$before" == "$after" ]] || fail 'el preflight modificó HOME'
grep -Fq '✓ git (ya instalado)' "$TEST_ROOT/preflight.out" || fail 'no clasificó paquete presente'
grep -Fq '+ grc' "$TEST_ROOT/preflight.out" || fail 'no clasificó paquete ausente'
grep -Fq '✓ Oh My Zsh (ya existe)' "$TEST_ROOT/preflight.out" || fail 'no detectó upstream existente'
grep -Fq '+ Powerlevel10k' "$TEST_ROOT/preflight.out" || fail 'no detectó upstream ausente'
grep -Fq '! ~/.zshrc ya existe' "$TEST_ROOT/preflight.out" || fail 'no mostró conflicto Stow'
grep -Fq 'No se sobrescribirán' "$TEST_ROOT/preflight.out" || fail 'no explicó política conservadora'

BACKUP_CONFLICTS=1
print_install_preflight personal > "$TEST_ROOT/backup.out"
grep -Fq 'Se respaldarán solo después de confirmar' "$TEST_ROOT/backup.out" || fail 'backup-conflicts no cambió solo el plan'
[[ "$before" == "$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)" ]] || fail 'backup-conflicts movió algo en preflight'

printf 'OK: preflight read-only de paquetes, upstream y conflictos\n'
