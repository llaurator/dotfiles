#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
TEST_CYCLE_DIR="$TEST_ROOT/cycle"
mkdir -p "$HOME" "$FAKE_BIN" "$TEST_CYCLE_DIR"
PATH="$FAKE_BIN:$PATH"
export HOME PATH

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_line() { grep -Fxq "$2" "$1" || fail "no se encontró '$2' en $1"; }

BASELINE_MODE=active
BASELINE_FORMAT=2
ACTIVE_CYCLE_DIR="$TEST_CYCLE_DIR"
DOTFILES_DISTRO=fedora
DOTFILES_ROOT="$ROOT_DIR"
DOTFILES_LOGIN_SHELL=/bin/bash

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == -qa ]]; then cat "$HOME/installed.txt"; exit; fi' \
  'if [[ "$1" == -q ]]; then grep -Fxq -- "$3" "$HOME/installed.txt"; exit; fi' \
  'exit 1' > "$FAKE_BIN/rpm"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "dnf %s\n" "$*" >> "$HOME/manager.log"' \
  'if [[ " $* " == *" install -y A "* ]]; then printf "%s\n" A B C >> "$HOME/installed.txt"; sort -u -o "$HOME/installed.txt" "$HOME/installed.txt"; exit; fi' \
  'if [[ " $* " == *" remove --assumeno "* ]]; then exit 1; fi' \
  'if [[ " $* " == *" remove -y --no-autoremove "* ]]; then for package in "$@"; do case "$package" in A|B|C) grep -Fvx -- "$package" "$HOME/installed.txt" > "$HOME/installed.tmp" || true; mv "$HOME/installed.tmp" "$HOME/installed.txt";; esac; done; exit; fi' \
  'exit 99' > "$FAKE_BIN/dnf"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' > "$FAKE_BIN/sudo"
chmod +x "$FAKE_BIN/rpm" "$FAKE_BIN/dnf" "$FAKE_BIN/sudo"

get_system_packages() { SYSTEM_PACKAGES=(A B C); }

reset_cycle() {
  rm -rf -- "$ACTIVE_CYCLE_DIR/package-snapshots"
  rm -f -- "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
  printf 'package\tmanager\tstate\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
  printf 'key\tbefore\tafter\nlogin_shell\t/bin/bash\t-\n' > "$ACTIVE_CYCLE_DIR/environment.tsv"
  printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\n' > "$ACTIVE_CYCLE_DIR/upstream.tsv"
  printf 'relative_path\texisted_before\ttype\tmode\tinstalled_mode\n' > "$ACTIVE_CYCLE_DIR/directories.tsv"
  printf 'relative_path\tbefore_fingerprint\tinstalled_fingerprint\n' > "$ACTIVE_CYCLE_DIR/fonts.tsv"
  : > "$HOME/manager.log"
}

# A solicitado introduce B como dependencia y C como weak dependency. Los tres
# están ausentes en el snapshot previo y presentes en el posterior.
reset_cycle
printf 'base\n' > "$HOME/installed.txt"
# Una baseline v2 anterior, sin los manifests opcionales nuevos, sigue siendo válida.
validate_environment_manifest
record_packages_before
run_tracked_package_transaction install-A sudo dnf install -y A
record_packages_after
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'A\tdnf\tinstalled_by_cycle'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'B\tdnf\tinstalled_by_cycle'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'C\tdnf\tinstalled_by_cycle'
[[ "$(find "$ACTIVE_CYCLE_DIR/package-snapshots" -type f | wc -l | tr -d ' ')" == 2 ]] || fail 'no se conservaron ambos snapshots de la transacción'
validate_package_transactions

print_environment_restore_plan 0 > "$TEST_ROOT/dry-run-plan.out"
awk '/Paquetes instalados por este ciclo:/{on=1;next}/Paquetes que ya existían:/{on=0} on && /^  retirar /{print}' "$TEST_ROOT/dry-run-plan.out" > "$TEST_ROOT/dry-run-packages.out"
printf '  retirar A\n  retirar B\n  retirar C\n' > "$TEST_ROOT/expected-dry-run.out"
cmp -s "$TEST_ROOT/expected-dry-run.out" "$TEST_ROOT/dry-run-packages.out" || fail 'dry-run no listó exactamente A/B/C'
preflight_package_removal
remove_cycle_packages
assert_line "$HOME/installed.txt" base
[[ "$(wc -l < "$HOME/installed.txt" | tr -d ' ')" == 1 ]] || fail 'rollback no retiró exactamente A/B/C'

# Si B y C ya existían, la diferencia solo atribuye A y ambos se conservan.
reset_cycle
printf 'B\nC\nbase\n' > "$HOME/installed.txt"
record_packages_before
run_tracked_package_transaction install-A sudo dnf install -y A
record_packages_after
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'A\tdnf\tinstalled_by_cycle'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'B\tdnf\talready_present'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'C\tdnf\talready_present'
remove_cycle_packages
assert_line "$HOME/installed.txt" B
assert_line "$HOME/installed.txt" C
if grep -Fxq A "$HOME/installed.txt"; then fail 'rollback conservó A introducido por el ciclo'; fi

# --keep-packages muestra y conserva toda la diferencia sin invocar una retirada.
reset_cycle
printf 'base\n' > "$HOME/installed.txt"
record_packages_before
run_tracked_package_transaction install-A sudo dnf install -y A
record_packages_after
: > "$HOME/manager.log"
print_environment_restore_plan 1 > "$TEST_ROOT/keep-plan.out"
for package in A B C; do
  grep -Fq "conservar $package" "$TEST_ROOT/keep-plan.out" || fail "--keep-packages no conservó $package"
  assert_line "$HOME/installed.txt" "$package"
done
[[ ! -s "$HOME/manager.log" ]] || fail '--keep-packages ejecutó el gestor de paquetes'

# Los demás gestores soportados también exponen inventarios completos, no solo
# la lista solicitada, usando exclusivamente dobles de prueba.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == -Qq ]] && printf "arch-b\narch-a\n"' > "$FAKE_BIN/pacman"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "deb:amd64\tii \nold\trc \n"' > "$FAKE_BIN/dpkg-query"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'case "$2" in --formula) printf "formula-b\nformula-a\n";; --cask) printf "cask-a\n";; esac' > "$FAKE_BIN/brew"
chmod +x "$FAKE_BIN/pacman" "$FAKE_BIN/dpkg-query" "$FAKE_BIN/brew"
DOTFILES_DISTRO=arch
[[ "$(list_installed_packages)" == $'arch-a\narch-b' ]] || fail 'snapshot Arch incompleto'
DOTFILES_DISTRO=debian
[[ "$(list_installed_packages)" == 'deb:amd64' ]] || fail 'snapshot Debian incompleto'
DOTFILES_DISTRO=macos
[[ "$(list_installed_packages)" == $'cask-a\nformula-a\nformula-b' ]] || fail 'snapshot Homebrew incompleto'

printf 'OK: snapshots de paquetes incluyen dependencias normales y débiles sin autoremove\n'
