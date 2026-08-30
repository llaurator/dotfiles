#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"; XDG_STATE_HOME="$TEST_ROOT/state"; export HOME XDG_STATE_HOME
source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/zsh_components.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
make_component() { local directory="$1" component="$2"; mkdir -p "$directory"; : > "$directory/$(zsh_component_marker "$component")"; }
make_home_component() { make_component "$(zsh_component_managed_dir "$1")" "$1"; }
assert_clone_count() { [[ "${#GIT_CLONES[@]}" == "$1" ]] || fail "clones: ${#GIT_CLONES[@]} != $1"; }
reset_home() { rm -rf "$HOME" "$XDG_STATE_HOME" "$TEST_ROOT/system"; mkdir -p "$HOME"; GIT_CLONES=(); DOTFILES_ZSH_SYSTEM_ROOT="$TEST_ROOT/system"; DOTFILES_DISTRO=other; FORCE_MANAGED=0; BASELINE_MODE=none; }

GIT_CLONES=()
git() {
  local destination component
  if [[ "$1" == -C && "$3" == rev-parse ]]; then printf 'test-commit'; return 0; fi
  [[ "$1" == clone ]] || return 0
  destination="${!#}"; GIT_CLONES+=("$destination")
  for component in omz p10k autosuggestions syntax history; do
    [[ "$destination" == "$(zsh_component_managed_dir "$component")" ]] || continue
    make_component "$destination" "$component"
    return 0
  done
  return 1
}
zsh_component_is_managed() { [[ "$FORCE_MANAGED" == 1 ]]; }
mark_path_if_changed() { :; }
prepare_upstream_state() {
  ACTIVE_CYCLE_DIR="$XDG_STATE_HOME/dotfiles/cycles/test"
  mkdir -p "$ACTIVE_CYCLE_DIR"
  printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\n' > "$ACTIVE_CYCLE_DIR/upstream.tsv"
  BASELINE_MODE=active; BASELINE_FORMAT=2
}

# Todos externos: no se clona ni se modifica nada.
reset_home
for component in omz p10k autosuggestions syntax history; do make_home_component "$component"; done
external_before="$(find "$HOME/.oh-my-zsh" -type f -printf '%P:%s\n' | LC_ALL=C sort)"
install_resolved_zsh_components
assert_clone_count 0
[[ "$external_before" == "$(find "$HOME/.oh-my-zsh" -type f -printf '%P:%s\n' | LC_ALL=C sort)" ]] || fail 'un external fue modificado'
prepare_upstream_state; record_upstream_before; record_upstream_after
awk -F '\t' 'NR > 1 && $3 != "yes" { exit 1 }' "$ACTIVE_CYCLE_DIR/upstream.tsv" || fail 'un external apareció como creado por el ciclo'

# Todos pendientes: cada componente se clona y queda en la lista atribuible.
reset_home
prepare_upstream_state; record_upstream_before
install_resolved_zsh_components
assert_clone_count 5
for component in omz p10k autosuggestions syntax history; do zsh_component_created "$component" || fail "$component no quedó marcado como creado"; done
record_upstream_after
awk -F '\t' 'NR > 1 && ($3 != "no" || $5 != "test-commit") { exit 1 }' "$ACTIVE_CYCLE_DIR/upstream.tsv" || fail 'un clone pendiente no quedó atribuido al ciclo'

# Todos gestionados: se reutilizan sin clones.
reset_home; FORCE_MANAGED=1
for component in omz p10k autosuggestions syntax history; do make_home_component "$component"; done
install_resolved_zsh_components
assert_clone_count 0

# Rutas mixtas de sistema y HOME: solo syntax falta y se genera una configuración estática.
reset_home; DOTFILES_DISTRO=arch
make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/oh-my-zsh" omz
make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/zsh-theme-powerlevel10k" p10k
make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/zsh/plugins/zsh-autosuggestions" autosuggestions
make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/zsh/plugins/zsh-history-substring-search" history
install_resolved_zsh_components
assert_clone_count 1
[[ "${GIT_CLONES[0]}" == "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]] || fail 'el componente mixto incorrecto se clonó'
BASELINE_MODE=active; BASELINE_FORMAT=2
OWNERSHIP_FILE="$TEST_ROOT/ownership.tsv"
printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
mkdir -p "$HOME/.config/dotfiles"
printf 'configuración local anterior\n' > "$HOME/.config/dotfiles/zsh-components.zsh"
write_resolved_zsh_component_config
config="$HOME/.config/dotfiles/zsh-components.zsh"
grep -Fqx 'configuración local anterior' "$config" && fail 'no se reemplazó una configuración previa respaldable'
grep -Fqx "export ZSH=$TEST_ROOT/system/usr/share/oh-my-zsh" "$config" || fail 'OMZ mixto no quedó configurado'
grep -Fqx "DOTFILES_P10K_THEME=$TEST_ROOT/system/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme" "$config" || fail 'P10k mixto no quedó configurado'
grep -Fqx "DOTFILES_ZSH_SYNTAX_HIGHLIGHTING=$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" "$config" || fail 'syntax gestionado no quedó configurado'
printf '%s\tzsh_components\t%s\t-\n' '.config/dotfiles/zsh-components.zsh' "$(path_fingerprint "$config")" >> "$OWNERSHIP_FILE"
printf 'cambio posterior del usuario\n' > "$config"
write_resolved_zsh_component_config
grep -Fqx 'cambio posterior del usuario' "$config" || fail 'se sobrescribió una modificación posterior del archivo generado'

printf 'OK: instalación Zsh respeta resolución managed/external/missing y rutas mixtas\n'
