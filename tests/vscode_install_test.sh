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
source "$ROOT_DIR/scripts/fedora.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command_exists() { if [[ "$1" == code ]]; then [[ -x "$FAKE_BIN/code" ]]; else command -v "$1" >/dev/null 2>&1; fi; }

ASSUME_YES=1
INSTALL_VSCODE=0
REQUEST_INSTALL_VSCODE=0
DOTFILES_OS=linux
DOTFILES_DISTRO=fedora
BASELINE_MODE=active
BASELINE_FORMAT=2
ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"
FEDORA_VSCODE_REPO_FILE="$TEST_ROOT/vscode.repo"
DOTFILES_ROOT="$ROOT_DIR"
DOTFILES_LOGIN_SHELL=/bin/bash
printf 'key\tbefore\tafter\nlogin_shell\t/bin/bash\t-\n' > "$ACTIVE_CYCLE_DIR/environment.tsv"
printf 'package\tmanager\tstate\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\n' > "$ACTIVE_CYCLE_DIR/upstream.tsv"

# La selección es opt-in: --yes no basta, server nunca pregunta y un code
# preexistente prevalece incluso ante el flag explícito.
select_vscode_install personal
[[ "$REQUEST_INSTALL_VSCODE" -eq 0 ]] || fail '--yes activó VS Code automáticamente'
select_vscode_install server < /dev/null
[[ "$REQUEST_INSTALL_VSCODE" -eq 0 ]] || fail 'server activó VS Code'
ASSUME_YES=0
select_vscode_install personal <<< 'n'
[[ "$REQUEST_INSTALL_VSCODE" -eq 0 ]] || fail 'la respuesta no activó VS Code'
select_vscode_install personal <<< 's'
[[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]] || fail 'la respuesta sí no activó VS Code'
ASSUME_YES=1
INSTALL_VSCODE=1
select_vscode_install personal
[[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]] || fail '--install-vscode no activó VS Code'
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/code"
chmod +x "$FAKE_BIN/code"
select_vscode_install personal
[[ "$REQUEST_INSTALL_VSCODE" -eq 0 ]] || fail 'code preexistente se consideró instalable por el ciclo'
get_system_packages || true
for package in "${SYSTEM_PACKAGES[@]}"; do [[ "$package" != code ]] || fail 'code preexistente entró en el tracking de paquetes'; done
rm -- "$FAKE_BIN/code"

# Dobles de Fedora: ninguna orden o repositorio real se toca.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == -qa ]]; then [[ ! -e "$HOME/code-installed" ]] || printf "code\n"; exit; fi' \
  'if [[ "$1" == -q ]]; then [[ "$3" == code && -e "$HOME/code-installed" ]]; exit; fi' \
  'if [[ "$1" == --import ]]; then printf "rpm %s\n" "$*" >> "$HOME/manager.log"; exit; fi' \
  'exit 1' > "$FAKE_BIN/rpm"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "dnf %s\n" "$*" >> "$HOME/manager.log"' \
  'case " $* " in *" install -y code "*) : > "$HOME/code-installed";; *" remove -y --no-autoremove code "*) rm -f -- "$HOME/code-installed";; esac' \
  'exit 0' > "$FAKE_BIN/dnf"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == install ]]; then /usr/bin/install -m 0644 "${@: -2:1}" "${@: -1}"; else exec "$@"; fi' \
  > "$FAKE_BIN/sudo"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'output=' \
  'while (( $# )); do case "$1" in -o) output=$2; shift 2;; *) shift;; esac; done' \
  'printf "test-key\n" > "$output"' > "$FAKE_BIN/curl"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'content=$(cat)' \
  'if [[ "$content" == test-key ]]; then printf "2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6  -\n"; else printf "%s" "$content" | /usr/bin/sha256sum; fi' \
  > "$FAKE_BIN/sha256sum"
chmod +x "$FAKE_BIN/rpm" "$FAKE_BIN/dnf" "$FAKE_BIN/sudo" "$FAKE_BIN/curl" "$FAKE_BIN/sha256sum"

INSTALL_VSCODE=1
REQUEST_INSTALL_VSCODE=1
record_packages_before
install_fedora_vscode
record_packages_after
grep -Fq $'code\tdnf\tinstalled_by_cycle' "$ACTIVE_CYCLE_DIR/packages.tsv" || fail 'code no quedó registrado como installed_by_cycle'
grep -Fq $'fedora_vscode_repository\tmissing\tfile:' "$ACTIVE_CYCLE_DIR/environment.tsv" || fail 'el repo creado no quedó registrado'
grep -Fxq 'baseurl=https://packages.microsoft.com/yumrepos/vscode' "$FEDORA_VSCODE_REPO_FILE" || fail 'se usó un repositorio Fedora no oficial'
grep -Fxq 'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' "$FEDORA_VSCODE_REPO_FILE" || fail 'se usó una clave Fedora no oficial'

remove_cycle_packages
[[ ! -e "$HOME/code-installed" ]] || fail 'rollback no retiró code instalado por el ciclo'
remove_fedora_vscode_repository
[[ ! -e "$FEDORA_VSCODE_REPO_FILE" ]] || fail 'rollback no retiró el repo intacto creado por el ciclo'

# Un repo modificado después de instalarse nunca se elimina.
printf 'package\tmanager\tstate\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
awk -F '\t' '$1 != "fedora_vscode_repository"' "$ACTIVE_CYCLE_DIR/environment.tsv" > "$TEST_ROOT/environment.tmp"
mv "$TEST_ROOT/environment.tmp" "$ACTIVE_CYCLE_DIR/environment.tsv"
REQUEST_INSTALL_VSCODE=1
install_fedora_vscode
printf '# cambio posterior\n' >> "$FEDORA_VSCODE_REPO_FILE"
remove_fedora_vscode_repository
[[ -f "$FEDORA_VSCODE_REPO_FILE" ]] || fail 'rollback borró un repo modificado por el usuario'

# Un repo oficial preexistente tampoco se atribuye al ciclo.
rm -- "$FEDORA_VSCODE_REPO_FILE"
printf '%s\n' \
  '[code]' \
  'name=Visual Studio Code' \
  'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
  'enabled=1' \
  'gpgcheck=1' \
  'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' > "$FEDORA_VSCODE_REPO_FILE"
awk -F '\t' '$1 != "fedora_vscode_repository"' "$ACTIVE_CYCLE_DIR/environment.tsv" > "$TEST_ROOT/environment.tmp"
mv "$TEST_ROOT/environment.tmp" "$ACTIVE_CYCLE_DIR/environment.tsv"
install_fedora_vscode
remove_fedora_vscode_repository
[[ -f "$FEDORA_VSCODE_REPO_FILE" ]] || fail 'rollback borró un repo oficial preexistente'

# El plan de --keep-packages conserva paquete y repositorio.
printf 'code\tdnf\tinstalled_by_cycle\n' >> "$ACTIVE_CYCLE_DIR/packages.tsv"
print_environment_restore_plan 1 > "$TEST_ROOT/keep-plan.out"
grep -Fq 'conservar code' "$TEST_ROOT/keep-plan.out" || fail '--keep-packages no conservó code en el plan'
grep -Fq "conservar $FEDORA_VSCODE_REPO_FILE" "$TEST_ROOT/keep-plan.out" || fail '--keep-packages no conservó el repo en el plan'

printf 'OK: VS Code Fedora opt-in, tracking y rollback seguro del repositorio\n'
