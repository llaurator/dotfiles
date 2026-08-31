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
printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == -v ]] && exit 0' 'exec "$@"' > "$FAKE_BIN/sudo"
printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in -u) printf "1000\n";; -un) printf "test-user\n";; *) exit 2;; esac' > "$FAKE_BIN/id"
chmod +x "$FAKE_BIN/rpm" "$FAKE_BIN/dnf" "$FAKE_BIN/sudo" "$FAKE_BIN/id"

get_system_packages() { SYSTEM_PACKAGES=(A B C); }
current_login_shell() { printf '%s\n' /bin/bash; }

reset_cycle() {
  rm -rf -- "$ACTIVE_CYCLE_DIR/package-snapshots"
  rm -f -- "$ACTIVE_CYCLE_DIR/package-transactions.tsv" "$ACTIVE_CYCLE_DIR/restore-journal.tsv" "$ACTIVE_CYCLE_DIR/restore.log"
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

# Si el gestor falla antes de instalar nada, los snapshots completos e iguales
# conservan pending como estado recuperable, sin atribuir paquetes al ciclo.
reset_cycle
printf 'base\n' > "$HOME/installed.txt"
record_packages_before
if run_tracked_package_transaction interrupted false; then fail 'un fallo del gestor devolvió éxito'; fi
validate_package_transactions
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'A\tdnf\tpending'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'B\tdnf\tpending'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'C\tdnf\tpending'
before_sha="$(awk -F '\t' 'NR == 2 {print $6}' "$ACTIVE_CYCLE_DIR/package-transactions.tsv")"
after_sha="$(awk -F '\t' 'NR == 2 {print $7}' "$ACTIVE_CYCLE_DIR/package-transactions.tsv")"
[[ "$before_sha" == "$after_sha" ]] || fail 'una transacción sin cambios no conservó snapshots idénticos'
preflight_environment_restore 0
print_environment_restore_plan 0 > "$TEST_ROOT/interrupted-plan.out"
if grep -Fq 'retirar A' "$TEST_ROOT/interrupted-plan.out"; then fail 'dry-run atribuyó un pending sin diferencia verificable'; fi
remove_cycle_packages
assert_line "$HOME/installed.txt" base
[[ ! -s "$HOME/manager.log" ]] || fail 'rollback invocó el gestor sin paquetes atribuibles'

# Una segunda ejecución reutiliza la misma baseline: la transacción posterior
# completa reconcilia únicamente los paquetes demostrados por su diferencia.
run_tracked_package_transaction install-A sudo dnf install -y A
record_packages_after
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'A\tdnf\tinstalled_by_cycle'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'B\tdnf\tinstalled_by_cycle'
assert_line "$ACTIVE_CYCLE_DIR/packages.tsv" $'C\tdnf\tinstalled_by_cycle'
[[ "$(awk 'END {print NR - 1}' "$ACTIVE_CYCLE_DIR/package-transactions.tsv")" == 2 ]] || fail 'la reanudación no conservó ambas transacciones'
validate_package_transactions

# Una entrada pending solo es atribuible con una diferencia completa y con
# hashes correctos; el estado legacy pending no bloquea su rollback.
package_tracking_set A dnf pending
preflight_package_removal
remove_cycle_packages
if grep -Fxq A "$HOME/installed.txt"; then fail 'pending demostrado por snapshots no se retiró'; fi

# Un paquete pendiente que hoy exista, pero no aparezca en after-before, es
# externo y se conserva aunque una transacción completa esté registrada.
reset_cycle
printf 'A\nbase\n' > "$HOME/installed.txt"
record_packages_before
package_tracking_set A dnf pending
run_tracked_package_transaction unchanged true
validate_package_transactions
package_is_cycle_owned A dnf pending && fail 'se atribuyó un pending sin diferencia de transacción'
remove_cycle_packages
assert_line "$HOME/installed.txt" A

# Un snapshot after ausente deja la evidencia incompleta: se conserva pending
# y el preflight/rollback puede continuar con el resto de categorías.
reset_cycle
printf 'A\nbase\n' > "$HOME/installed.txt"
printf 'package\tmanager\tstate\nA\tdnf\tpending\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
mkdir -p "$ACTIVE_CYCLE_DIR/package-snapshots"
printf 'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256\n' > "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
printf '0001\tdnf\tincomplete\tpackage-snapshots/0001-before.txt\tpackage-snapshots/0001-after.txt\t-\t-\n' >> "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
validate_package_transactions
preflight_environment_restore 0
remove_cycle_packages
assert_line "$HOME/installed.txt" A

# Si sí existe evidencia y su SHA-256 no coincide, sigue siendo corrupción y
# debe abortar antes de que el rollback toque paquetes.
reset_cycle
printf 'base\n' > "$HOME/installed.txt"
record_packages_before
run_tracked_package_transaction install-A sudo dnf install -y A
printf 'metadata-manipulada\n' >> "$ACTIVE_CYCLE_DIR/package-snapshots/0001-after.txt"
if (validate_package_transactions); then fail 'un SHA-256 corrupto fue aceptado'; fi

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

# Una baseline anterior puede contener snapshots íntegros ordenados con una
# collation diferente. Se verifica primero el hash y se compara únicamente una
# copia temporal normalizada, sin tocar la evidencia original.
legacy_cycle="$TEST_ROOT/legacy-locale-cycle"
mkdir -p "$legacy_cycle/package-snapshots"
legacy_before="$legacy_cycle/package-snapshots/0001-before.txt"
legacy_after="$legacy_cycle/package-snapshots/0001-after.txt"
before_input="$TEST_ROOT/legacy-before-input.txt"
after_input="$TEST_ROOT/legacy-after-input.txt"
printf '%s\n' alpha Alpha PackageKit PackageKit-command-not-found PackageKit-Qt6 pkg-2 pkg-10 zeta-1 > "$before_input"
printf '%s\n' alpha Alpha Beta-2 beta-10 PackageKit PackageKit-command-not-found PackageKit-Qt6 pkg-2 pkg-10 rocm-smi zeta-1 > "$after_input"
test_locale="$(locale -a | awk 'tolower($0) ~ /^es_es\.(utf-?8|utf8)$/ {print; exit}')"
if [[ -n "$test_locale" ]]; then
  LC_ALL="$test_locale" sort -u "$before_input" > "$legacy_before"
  LC_ALL="$test_locale" sort -u "$after_input" > "$legacy_after"
else
  # Orden deliberadamente incompatible con C para entornos sin locale español.
  printf '%s\n' alpha Alpha PackageKit PackageKit-command-not-found PackageKit-Qt6 pkg-2 pkg-10 zeta-1 > "$legacy_before"
  printf '%s\n' alpha Alpha Beta-2 beta-10 PackageKit PackageKit-command-not-found PackageKit-Qt6 pkg-2 pkg-10 rocm-smi zeta-1 > "$legacy_after"
  test_locale=C
fi
if LC_ALL=C sort -cu "$legacy_before" >/dev/null 2>&1; then fail 'la fixture legacy quedó accidentalmente ordenada en C'; fi
legacy_before_sha="$(sha256_stream < "$legacy_before")"
legacy_after_sha="$(sha256_stream < "$legacy_after")"
legacy_before_bytes="$(cksum "$legacy_before")"
legacy_after_bytes="$(cksum "$legacy_after")"
printf 'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256\n' > "$legacy_cycle/package-transactions.tsv"
printf '0001\tdnf\tlegacy-locale\tpackage-snapshots/0001-before.txt\tpackage-snapshots/0001-after.txt\t%s\t%s\n' \
  "$legacy_before_sha" "$legacy_after_sha" >> "$legacy_cycle/package-transactions.tsv"
printf 'package\tmanager\tstate\nBeta-2\tdnf\tinstalled_by_cycle\nbeta-10\tdnf\tinstalled_by_cycle\nrocm-smi\tdnf\tinstalled_by_cycle\n' \
  > "$legacy_cycle/packages.tsv"
ACTIVE_CYCLE_DIR="$legacy_cycle"
LC_ALL="$test_locale" validate_package_transactions > "$TEST_ROOT/legacy-validation.out" 2> "$TEST_ROOT/legacy-validation.err"
[[ ! -s "$TEST_ROOT/legacy-validation.err" ]] || fail 'la validación legacy emitió warnings de comm'
[[ "$(cksum "$legacy_before")" == "$legacy_before_bytes" && "$(cksum "$legacy_after")" == "$legacy_after_bytes" ]] ||
  fail 'la comparación modificó un snapshot legacy'
[[ "$(sha256_stream < "$legacy_before")" == "$legacy_before_sha" && "$(sha256_stream < "$legacy_after")" == "$legacy_after_sha" ]] ||
  fail 'la comparación invalidó el SHA-256 original'
LC_ALL="$test_locale" package_snapshot_difference "$legacy_before" "$legacy_after" \
  > "$TEST_ROOT/legacy-difference.out" 2> "$TEST_ROOT/legacy-difference.err"
printf 'Beta-2\nbeta-10\nrocm-smi\n' > "$TEST_ROOT/legacy-expected.out"
cmp -s "$TEST_ROOT/legacy-expected.out" "$TEST_ROOT/legacy-difference.out" || fail 'after-before no produjo el conjunto canónico correcto'
[[ ! -s "$TEST_ROOT/legacy-difference.err" ]] || fail 'comm emitió warnings al comparar copias normalizadas'

# Los snapshots nuevos son canónicos incluso si la sesión usa otra collation.
printf '%s\n' zeta-1 pkg-2 alpha PackageKit-Qt6 pkg-10 Alpha PackageKit-command-not-found > "$HOME/installed.txt"
canonical_snapshot="$legacy_cycle/package-snapshots/new-canonical.txt"
LC_ALL="$test_locale" capture_package_snapshot "$canonical_snapshot"
LC_ALL=C sort -cu "$canonical_snapshot" || fail 'un snapshot nuevo no quedó ordenado en C'

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
