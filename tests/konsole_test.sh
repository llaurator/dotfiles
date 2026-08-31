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
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_file() { [[ -f "$1" && ! -L "$1" ]] || fail "falta $1"; }

DOTFILES_ROOT="$ROOT_DIR"
DOTFILES_OS=linux
DOTFILES_DISTRO=fedora
ASSUME_YES=1
CONFIGURE_KONSOLE=0
REQUEST_CONFIGURE_KONSOLE=0
BASELINE_MODE=active
BASELINE_FORMAT=2
ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"
MANIFEST_FILE="$ACTIVE_CYCLE_DIR/manifest.tsv"
OWNERSHIP_FILE="$ACTIVE_CYCLE_DIR/ownership.tsv"
printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$MANIFEST_FILE"
printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
printf 'action\tresource\tstate\n' > "$ACTIVE_CYCLE_DIR/restore-journal.tsv"

# Konsole ausente: no se pregunta ni se solicita configuración.
select_konsole_configure personal < /dev/null
[[ "$REQUEST_CONFIGURE_KONSOLE" -eq 0 ]] || fail 'Konsole ausente activó la configuración'

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/konsole"
printf '%s\n' '#!/usr/bin/env bash' 'printf "MesloLGS Nerd Font\n"' > "$FAKE_BIN/fc-query"
chmod +x "$FAKE_BIN/konsole" "$FAKE_BIN/fc-query"

# server y --yes sin flag nunca lo activan; un NO interactivo tampoco.
select_konsole_configure server < /dev/null
[[ "$REQUEST_CONFIGURE_KONSOLE" -eq 0 ]] || fail 'server activó Konsole'
select_konsole_configure personal < /dev/null
[[ "$REQUEST_CONFIGURE_KONSOLE" -eq 0 ]] || fail '--yes activó Konsole'
ASSUME_YES=0
select_konsole_configure personal <<< 'n'
[[ "$REQUEST_CONFIGURE_KONSOLE" -eq 0 ]] || fail 'NO interactivo activó Konsole'
ASSUME_YES=1

printf 'fixture dracula\n' > "$TEST_ROOT/Dracula.colorscheme"
DOTFILES_KONSOLE_SHA256="$(sha256sum "$TEST_ROOT/Dracula.colorscheme" | awk '{print $1}')"
export DOTFILES_KONSOLE_SHA256
# shellcheck disable=SC2016 # El contenido se evalúa en el doble curl de pruebas.
printf '%s\n' '#!/usr/bin/env bash' \
  'out=' \
  'while (( $# )); do case "$1" in -o) out=$2; shift 2;; *) shift;; esac; done' \
  'cp "$DOTFILES_KONSOLE_FIXTURE" "$out"' > "$FAKE_BIN/curl"
chmod +x "$FAKE_BIN/curl"
export DOTFILES_KONSOLE_FIXTURE="$TEST_ROOT/Dracula.colorscheme"
mkdir -p "$HOME/.local/share/fonts"
printf 'font fixture\n' > "$HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf"

# La baseline preserva el default anterior y configura solo la clave necesaria.
mkdir -p "$HOME/.config"
printf '[Desktop Entry]\nDefaultProfile=User.profile\nOther=keep\n\n[Other]\nKey=keep\n' > "$HOME/.config/konsolerc"
record_baseline_path '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles-Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
record_baseline_path '.config/konsolerc' konsole_config '-'
CONFIGURE_KONSOLE=1
select_konsole_configure personal
[[ "$REQUEST_CONFIGURE_KONSOLE" -eq 1 ]] || fail '--configure-konsole no activó Konsole'
MESLO_FONT_FAMILY='MesloLGS NF'
configure_konsole personal
assert_file "$HOME/.local/share/konsole/Dracula.colorscheme"
assert_file "$HOME/.local/share/konsole/Dotfiles.profile"
grep -Fxq 'ColorScheme=Dracula' "$HOME/.local/share/konsole/Dotfiles.profile" || fail 'perfil sin Dracula'
grep -Fxq 'Font=MesloLGS NF,10,-1,5,50,0,0,0,0,0' "$HOME/.local/share/konsole/Dotfiles.profile" || fail 'perfil sin fuente resuelta'
grep -Fxq 'DefaultProfile=Dotfiles.profile' "$HOME/.config/konsolerc" || fail 'default no actualizado'
grep -Fxq 'Other=keep' "$HOME/.config/konsolerc" || fail 'konsolerc no preservó otras claves'

# Idempotencia y rollback: solo se retira lo creado y se restaura el default exacto.
configure_konsole personal
remove_owned_configuration
restore_baseline_files
[[ ! -e "$HOME/.local/share/konsole/Dracula.colorscheme" ]] || fail 'rollback no retiró esquema propio'
[[ ! -e "$HOME/.local/share/konsole/Dotfiles.profile" ]] || fail 'rollback no retiró perfil propio'
grep -Fxq 'DefaultProfile=User.profile' "$HOME/.config/konsolerc" || fail 'rollback no restauró default previo'
grep -Fxq 'Other=keep' "$HOME/.config/konsolerc" || fail 'rollback no restauró konsolerc exacto'

# Hash incorrecto no deja instalación parcial.
rm -f "$HOME/.config/konsolerc"
printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$MANIFEST_FILE"
printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
printf 'action\tresource\tstate\n' > "$ACTIVE_CYCLE_DIR/restore-journal.tsv"
rm -f -- "$ACTIVE_CYCLE_DIR/restore.log"
record_baseline_path '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles-Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
record_baseline_path '.config/konsolerc' konsole_config '-'
DOTFILES_KONSOLE_SHA256='00'
REQUEST_CONFIGURE_KONSOLE=1
configure_konsole personal
[[ ! -e "$HOME/.local/share/konsole/Dracula.colorscheme" && ! -e "$HOME/.local/share/konsole/Dotfiles.profile" && ! -e "$HOME/.config/konsolerc" ]] || fail 'hash incorrecto dejó cambios parciales'

# Un Dracula externo distinto se conserva y permite configurar el perfil con
# el esquema propio, que sí queda atribuible al ciclo.
DOTFILES_KONSOLE_SHA256="$(sha256sum "$TEST_ROOT/Dracula.colorscheme" | awk '{print $1}')"
mkdir -p "$HOME/.local/share/konsole"
printf 'user scheme\n' > "$HOME/.local/share/konsole/Dracula.colorscheme"
printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$MANIFEST_FILE"
printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
printf 'action\tresource\tstate\n' > "$ACTIVE_CYCLE_DIR/restore-journal.tsv"
record_baseline_path '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles-Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
record_baseline_path '.config/konsolerc' konsole_config '-'
configure_konsole personal
[[ "$(< "$HOME/.local/share/konsole/Dracula.colorscheme")" == 'user scheme' ]] || fail 'se sobrescribió esquema preexistente'
assert_file "$HOME/.local/share/konsole/Dotfiles-Dracula.colorscheme"
grep -Fxq 'ColorScheme=Dotfiles-Dracula' "$HOME/.local/share/konsole/Dotfiles.profile" || fail 'perfil no usó el esquema separado'
remove_owned_configuration
restore_baseline_files
[[ "$(< "$HOME/.local/share/konsole/Dracula.colorscheme")" == 'user scheme' ]] || fail 'rollback tocó Dracula externo'
[[ ! -e "$HOME/.local/share/konsole/Dotfiles-Dracula.colorscheme" ]] || fail 'rollback no retiró el esquema propio'

# Un esquema alternativo preexistente que no coincide tampoco se sobrescribe.
printf 'conflicto propio\n' > "$HOME/.local/share/konsole/Dotfiles-Dracula.colorscheme"
rm -f -- "$HOME/.local/share/konsole/Dotfiles.profile"
configure_konsole personal
[[ "$(< "$HOME/.local/share/konsole/Dotfiles-Dracula.colorscheme")" == 'conflicto propio' ]] || fail 'se sobrescribió el esquema alternativo preexistente'
[[ ! -e "$HOME/.local/share/konsole/Dotfiles.profile" ]] || fail 'se configuró Konsole ante un esquema alternativo conflictivo'

# El Dracula externo que coincide con el pin se reutiliza sin reclamarlo.
rm -f -- "$HOME/.local/share/konsole/Dotfiles-Dracula.colorscheme"
cp "$TEST_ROOT/Dracula.colorscheme" "$HOME/.local/share/konsole/Dracula.colorscheme"
printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$MANIFEST_FILE"
printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
printf 'action\tresource\tstate\n' > "$ACTIVE_CYCLE_DIR/restore-journal.tsv"
rm -f -- "$ACTIVE_CYCLE_DIR/restore.log"
record_baseline_path '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles-Dracula.colorscheme' konsole_colorscheme '-'
record_baseline_path '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
record_baseline_path '.config/konsolerc' konsole_config '-'
configure_konsole personal
grep -Fxq 'ColorScheme=Dracula' "$HOME/.local/share/konsole/Dotfiles.profile" || fail 'no se reutilizó el Dracula externo idéntico'
if grep -Fq $'.local/share/konsole/Dracula.colorscheme\tkonsole_colorscheme' "$OWNERSHIP_FILE"; then fail 'se reclamó un Dracula externo idéntico'; fi

printf 'OK: Konsole opt-in, descarga verificada y rollback conservador\n'
