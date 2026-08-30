#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
XDG_STATE_HOME="$TEST_ROOT/state"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$HOME/.oh-my-zsh/.git" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git"
touch "$HOME/.oh-my-zsh/oh-my-zsh.sh" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$*" in *"MesloLGS Nerd Font"*) family=${FONTCONFIG_NERD_FONT_FAMILY:-Otra Nerd Font};; *"MesloLGS NF"*) family=${FONTCONFIG_NF_FAMILY:-Otra Nerd Font};; *) exit 1;; esac' \
  'printf "%s\n" "$family"' > "$FAKE_BIN/fc-match"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/fc-list"
# shellcheck disable=SC2016 # El doble escribe en el temporal del test al ejecutarse.
printf '%s\n' '#!/usr/bin/env bash' 'printf called >> "$TEST_ROOT/fc-cache.log"' > "$FAKE_BIN/fc-cache"
chmod +x "$FAKE_BIN/fc-match" "$FAKE_BIN/fc-list" "$FAKE_BIN/fc-cache"
PATH="$FAKE_BIN:$PATH"
export HOME XDG_STATE_HOME PATH TEST_ROOT

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/zsh_components.sh"
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
get_system_packages() { SYSTEM_PACKAGES=(git stow grc); }
package_is_installed() { [[ "$1" == git || "$1" == stow ]]; }
BACKUP_CONFLICTS=0
CONFLICT_RELS=(.zshrc)

state_snapshot() { [[ -e "$XDG_STATE_HOME" ]] && find "$XDG_STATE_HOME" -printf '%P:%y:%s\n' | LC_ALL=C sort || printf 'missing\n'; }
before="$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
state_before="$(state_snapshot)"
print_install_preflight personal > "$TEST_ROOT/preflight.out"
after="$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)"
[[ "$before" == "$after" ]] || fail 'el preflight modificó HOME'
[[ "$state_before" == "$(state_snapshot)" ]] || fail 'el preflight modificó STATE'
[[ ! -e "$TEST_ROOT/fc-cache.log" ]] || fail 'el preflight ejecutó fc-cache'
grep -Fq '✓ git (ya instalado)' "$TEST_ROOT/preflight.out" || fail 'no clasificó paquete presente'
grep -Fq '+ grc' "$TEST_ROOT/preflight.out" || fail 'no clasificó paquete ausente'
grep -Fq '✓ Oh My Zsh (externo)' "$TEST_ROOT/preflight.out" || fail 'reclamó upstream preexistente como gestionado'
grep -Fq '+ Powerlevel10k (pendiente)' "$TEST_ROOT/preflight.out" || fail 'no detectó upstream ausente'
grep -Fq '+ MesloLGS Nerd Font (se instalará)' "$TEST_ROOT/preflight.out" || fail 'no mostró la fuente pendiente'
grep -Fq '! ~/.zshrc ya existe' "$TEST_ROOT/preflight.out" || fail 'no mostró conflicto Stow'
grep -Fq 'No se sobrescribirán' "$TEST_ROOT/preflight.out" || fail 'no explicó política conservadora'

BACKUP_CONFLICTS=1
print_install_preflight personal > "$TEST_ROOT/backup.out"
grep -Fq 'Se respaldarán solo después de confirmar' "$TEST_ROOT/backup.out" || fail 'backup-conflicts no cambió solo el plan'
[[ "$before" == "$(find "$HOME" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)" ]] || fail 'backup-conflicts movió algo en preflight'
[[ "$state_before" == "$(state_snapshot)" ]] || fail 'backup-conflicts modificó STATE en preflight'
FONTCONFIG_NERD_FONT_FAMILY='Noto Sans' FONTCONFIG_NF_FAMILY='MesloLGS NF' print_install_preflight personal > "$TEST_ROOT/system-font.out"
grep -Fq '✓ MesloLGS NF (sistema)' "$TEST_ROOT/system-font.out" || fail 'no detectó MesloLGS NF del sistema'
FONTCONFIG_NERD_FONT_FAMILY='MesloLGS Nerd Font' FONTCONFIG_NF_FAMILY='MesloLGS NF' print_install_preflight personal > "$TEST_ROOT/preferred-font.out"
grep -Fq '✓ MesloLGS Nerd Font (sistema)' "$TEST_ROOT/preferred-font.out" || fail 'no respetó la preferencia de fuente'
[[ ! -e "$TEST_ROOT/fc-cache.log" ]] || fail 'el preflight con fuente de sistema ejecutó fc-cache'

printf 'OK: preflight read-only de paquetes, upstream y conflictos\n'
