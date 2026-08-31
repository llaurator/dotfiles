#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
SHELLS_FIXTURE="$TEST_ROOT/shells"
FAKE_ZSH="$TEST_ROOT/fake-bin/zsh"
mkdir -p "${FAKE_ZSH%/*}" "$TEST_ROOT/cycle"
printf '# simulated /etc/shells\n/bin/bash\n/bin/sh\n/usr/bin/zsh\n' > "$SHELLS_FIXTURE"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_ZSH"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${FAKE_ZSH%/*}/grep"
chmod +x "$FAKE_ZSH" "${FAKE_ZSH%/*}/grep"

# The parser is independently testable with a simulated /etc/shells, while
# production always supplies the real /etc/shells path to is_valid_login_shell.
login_shell_is_registered /usr/bin/zsh "$SHELLS_FIXTURE" || fail '/usr/bin/zsh registrado fue rechazado'
login_shell_is_registered /bin/bash "$SHELLS_FIXTURE" || fail '/bin/bash registrado fue rechazado'
if login_shell_is_registered "$FAKE_ZSH" "$SHELLS_FIXTURE"; then
  fail 'un zsh temporal fue aceptado por la lista simulada'
fi

DOTFILES_OS=linux
SYSTEM_ZSH="$(command -v zsh)"
is_valid_login_shell "$SYSTEM_ZSH" || fail "el zsh del sistema no está registrado: $SYSTEM_ZSH"
if is_valid_login_shell "$FAKE_ZSH"; then
  fail 'un zsh temporal fue aceptado como shell de login del host'
fi

# A manipulated PATH can find a fake zsh, but ensure_zsh_shell must never send
# it to privileged_chsh.
CHSH_CALLS="$TEST_ROOT/chsh-calls"
privileged_chsh() { printf '%s\n' "$1" >> "$CHSH_CALLS"; }
record_shell_changed() { :; }
current_login_shell() { printf '/bin/bash'; }
PATH="${FAKE_ZSH%/*}:$PATH"
ensure_zsh_shell > "$TEST_ROOT/ensure.out"
[[ ! -e "$CHSH_CALLS" ]] || fail 'ensure_zsh_shell intentó cambiar al zsh temporal'
/usr/bin/grep -Fq 'no es un shell de login válido' "$TEST_ROOT/ensure.out" || fail 'faltó el rechazo explícito del zsh temporal'

# The production check accepts the system zsh only if the real /etc/shells
# explicitly registers it. Calling the privileged layer is stubbed in this test.
PATH="${PATH#${FAKE_ZSH%/*}:}"
ensure_zsh_shell
[[ "$(< "$CHSH_CALLS")" == "$SYSTEM_ZSH" ]] || fail 'ensure_zsh_shell no aceptó el zsh registrado'

# A corrupt baseline must be rejected before a rollback can call chsh.
ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"
printf 'key\tbefore\tafter\nlogin_shell\t%s\t/bin/bash\n' "$FAKE_ZSH" > "$ACTIVE_CYCLE_DIR/environment.tsv"
DOTFILES_LOGIN_SHELL=/bin/bash
if (restore_login_shell) > "$TEST_ROOT/rollback.out" 2>&1; then
  fail 'rollback aceptó una baseline con shell temporal'
fi
[[ "$(< "$CHSH_CALLS")" == "$SYSTEM_ZSH" ]] || fail 'rollback corrupto llegó a chsh'

printf 'OK: validación de shells de login y rollback seguro\n'
