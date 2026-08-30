#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
PRIVILEGE_LOG="$TEST_ROOT/sudo.log"
CHSH_LOG="$TEST_ROOT/chsh.log"
MANAGER_LOG="$TEST_ROOT/manager.log"
mkdir -p "$HOME" "$FAKE_BIN" "$TEST_ROOT/cycle"
PATH="$FAKE_BIN:$PATH"
export HOME PATH PRIVILEGE_LOG CHSH_LOG MANAGER_LOG

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_count() {
  local expected="$1" pattern="$2" file="$3" actual
  actual="$(grep -Fc -- "$pattern" "$file" || true)"
  [[ "$actual" == "$expected" ]] || fail "se esperaban $expected coincidencias de '$pattern' y hubo $actual"
}

# Todos los comandos que podrían elevar privilegios son dobles locales.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'case "${1:-}" in -u) printf "%s\n" "$TEST_EFFECTIVE_UID";; -un) if [[ "$TEST_EFFECTIVE_UID" == 0 ]]; then printf "root\n"; else printf "test-user\n"; fi;; *) exit 2;; esac' \
  > "$FAKE_BIN/id"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "sudo %s\n" "$*" >> "$PRIVILEGE_LOG"' \
  'if [[ "${1:-}" == -v ]]; then [[ "${TEST_AUTH_FAIL:-0}" != 1 ]]; exit; fi' \
  'exec "$@"' > "$FAKE_BIN/sudo"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "chsh %s\n" "$*" >> "$CHSH_LOG"' \
  '[[ "${TEST_CHSH_FAIL:-0}" != 1 ]]' > "$FAKE_BIN/chsh"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "dnf %s\n" "$*" >> "$MANAGER_LOG"' > "$FAKE_BIN/dnf"
chmod +x "$FAKE_BIN/id" "$FAKE_BIN/sudo" "$FAKE_BIN/chsh" "$FAKE_BIN/dnf"

TEST_EFFECTIVE_UID=1000
TEST_AUTH_FAIL=0
TEST_CHSH_FAIL=0
export TEST_EFFECTIVE_UID TEST_AUTH_FAIL TEST_CHSH_FAIL
: > "$PRIVILEGE_LOG"; : > "$CHSH_LOG"; : > "$MANAGER_LOG"

# La primera operación valida sudo; chsh y el gestor posterior reutilizan el
# timestamp normal sin nuevas validaciones ni mecanismos de keepalive.
SUDO_VALIDATED=0
run_privileged dnf install -y zsh
privileged_chsh /usr/bin/zsh
run_privileged dnf remove -y tool-a
assert_count 1 'sudo -v' "$PRIVILEGE_LOG"
assert_count 1 'sudo dnf install -y zsh' "$PRIVILEGE_LOG"
assert_count 1 'sudo chsh -s /usr/bin/zsh test-user' "$PRIVILEGE_LOG"
assert_count 1 'sudo dnf remove -y tool-a' "$PRIVILEGE_LOG"
assert_count 1 'chsh -s /usr/bin/zsh test-user' "$CHSH_LOG"

# Root ejecuta exactamente las mismas herramientas, pero nunca invoca sudo.
TEST_EFFECTIVE_UID=0
SUDO_VALIDATED=0
: > "$PRIVILEGE_LOG"; : > "$CHSH_LOG"; : > "$MANAGER_LOG"
run_privileged dnf install -y zsh
privileged_chsh /bin/bash
[[ ! -s "$PRIVILEGE_LOG" ]] || fail 'root invocó sudo'
assert_count 1 'dnf install -y zsh' "$MANAGER_LOG"
assert_count 1 'chsh -s /bin/bash root' "$CHSH_LOG"

# Un fallo de sudo ocurre después del checkpoint started. El siguiente intento
# puede completar el mismo restore sin modificar ni falsificar la baseline.
TEST_EFFECTIVE_UID=1000
TEST_AUTH_FAIL=1
SUDO_VALIDATED=0
ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"
DOTFILES_LOGIN_SHELL=/usr/bin/zsh
printf 'key\tbefore\tafter\nlogin_shell\t/bin/bash\t/usr/bin/zsh\n' > "$ACTIVE_CYCLE_DIR/environment.tsv"
: > "$PRIVILEGE_LOG"; : > "$CHSH_LOG"
if (restore_login_shell); then fail 'la autenticación ficticia debía fallar'; fi
grep -Fqx $'shell_restore\tlogin_shell\tstarted' "$ACTIVE_CYCLE_DIR/restore-journal.tsv" ||
  fail 'el fallo de autenticación no dejó un checkpoint reanudable'
[[ ! -s "$CHSH_LOG" ]] || fail 'chsh se ejecutó pese al fallo de sudo'

TEST_AUTH_FAIL=0
SUDO_VALIDATED=0
restore_login_shell
grep -Fqx $'shell_restore\tlogin_shell\tcompleted' "$ACTIVE_CYCLE_DIR/restore-journal.tsv" ||
  fail 'el retry no completó el checkpoint de shell'

# --status es de solo lectura y no entra en la envoltura privilegiada.
: > "$PRIVILEGE_LOG"
mkdir -p "$TEST_ROOT/status-home"
HOME="$TEST_ROOT/status-home" XDG_STATE_HOME="$TEST_ROOT/status-home/.state" \
  DOTFILES_LOGIN_SHELL=/bin/bash "$ROOT_DIR/install.sh" --status > "$TEST_ROOT/status.out"
[[ ! -s "$PRIVILEGE_LOG" ]] || fail '--status invocó sudo'

printf 'OK: validación sudo única, chsh compartido, root y restore reanudable\n'
