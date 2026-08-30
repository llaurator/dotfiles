#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

REAL_GIT="$(command -v git)"
REMOTE_REPOSITORY="$TEST_ROOT/remote.git"
SEED_REPOSITORY="$TEST_ROOT/seed"
TEST_GIT_CONFIG="$TEST_ROOT/gitconfig"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    command grep -Fq -- "$2" "$1" || fail "no se encontró '$2' en $1"
}

assert_file_line() {
    command grep -Fxq -- "$2" "$1" || fail "no se encontró la línea '$2' en $1"
}

assert_files_equal() {
    command cmp -s -- "$1" "$2" || fail "los archivos $1 y $2 no coinciden"
}

git_test() {
    GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 "$REAL_GIT" "$@"
}

run_bootstrap() {
    local home="$1" output="$2"
    shift 2
    HOME="$home" GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 \
        BOOTSTRAP_TEST_ARGS_FILE="$home/installer-args" \
        BOOTSTRAP_TEST_ROOT_FILE="$home/installer-root" \
        bash -s -- "$@" < "$ROOT_DIR/bootstrap.sh" > "$output" 2>&1
}

run_bootstrap_in() {
    local home="$1" directory="$2" output="$3"
    shift 3
    HOME="$home" DOTFILES_DIR="$directory" GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" \
        GIT_CONFIG_NOSYSTEM=1 BOOTSTRAP_TEST_ARGS_FILE="$home/installer-args" \
        BOOTSTRAP_TEST_ROOT_FILE="$home/installer-root" \
        bash -s -- "$@" < "$ROOT_DIR/bootstrap.sh" > "$output" 2>&1
}

expect_bootstrap_failure() {
    if run_bootstrap_in "$@"; then
        fail 'el bootstrap debía haber fallado'
    fi
}

mkdir -p "$SEED_REPOSITORY"
git_test -C "$SEED_REPOSITORY" init -q -b main
cp "$ROOT_DIR/bootstrap.sh" "$SEED_REPOSITORY/bootstrap.sh"
# Las expansiones pertenecen al script ficticio, no a este proceso.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -Eeuo pipefail' \
    ': > "$BOOTSTRAP_TEST_ARGS_FILE"' \
    'if (( $# > 0 )); then printf "%s\n" "$@" > "$BOOTSTRAP_TEST_ARGS_FILE"; fi' \
    'cd -- "$(dirname -- "${BASH_SOURCE[0]}")"' \
    'pwd > "$BOOTSTRAP_TEST_ROOT_FILE"' \
    > "$SEED_REPOSITORY/install.sh"
chmod +x "$SEED_REPOSITORY/bootstrap.sh" "$SEED_REPOSITORY/install.sh"
git_test -C "$SEED_REPOSITORY" add bootstrap.sh install.sh
git_test -C "$SEED_REPOSITORY" -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.invalid' commit -qm 'initial fixture'
initial_commit="$(git_test -C "$SEED_REPOSITORY" rev-parse HEAD)"
git_test -C "$SEED_REPOSITORY" tag v1.1.0
git_test init -q --bare "$REMOTE_REPOSITORY"
git_test -C "$SEED_REPOSITORY" remote add origin "$REMOTE_REPOSITORY"
git_test -C "$SEED_REPOSITORY" push -q -u origin main --tags
git_test config --file "$TEST_GIT_CONFIG" \
    url."file://$REMOTE_REPOSITORY".insteadOf 'https://github.com/llaurator/dotfiles.git'

# A, G y H: clonado inicial por stdin, main y argumentos intactos.
case_a_home="$TEST_ROOT/case-a-home"
mkdir -p "$case_a_home"
case_a_repo="$case_a_home/.local/share/dotfiles"
run_bootstrap "$case_a_home" "$case_a_home/output" --ref main --profile server --yes
[[ -d "$case_a_repo/.git" ]] || fail 'no se realizó el clonado inicial'
printf '%s\n' '--profile' 'server' '--yes' > "$case_a_home/expected-args"
assert_files_equal "$case_a_home/expected-args" "$case_a_home/installer-args"
[[ "$(git_test -C "$case_a_repo" symbolic-ref --short HEAD)" == 'main' ]] ||
    fail 'la instalación inicial no quedó en main'
[[ "$(< "$case_a_home/installer-root")" == "$case_a_repo" ]] ||
    fail 'se ejecutó un install.sh distinto al del repositorio permanente'

# Sin argumentos, el bootstrap delega directamente en el modo interactivo del instalador.
interactive_home="$TEST_ROOT/interactive-home"
interactive_repo="$TEST_ROOT/interactive-repo"
mkdir -p "$interactive_home"
run_bootstrap_in "$interactive_home" "$interactive_repo" "$interactive_home/output"
[[ ! -s "$interactive_home/installer-args" ]] ||
    fail 'el bootstrap añadió argumentos en el modo interactivo'

# B: un repositorio actualizado se reutiliza, no se reclona.
git_test -C "$case_a_repo" config bootstrap.test-marker preserved
run_bootstrap "$case_a_home" "$case_a_home/current-output" --yes --profile server
[[ "$(git_test -C "$case_a_repo" config bootstrap.test-marker)" == 'preserved' ]] ||
    fail 'el repositorio existente fue reemplazado'
assert_contains "$case_a_home/current-output" 'ya está actualizado en main'

# Las acciones nuevas también atraviesan el bootstrap sin que este necesite conocerlas.
run_bootstrap "$case_a_home" "$case_a_home/status-output" --status
printf '%s\n' '--status' > "$case_a_home/expected-status-args"
assert_files_equal "$case_a_home/expected-status-args" "$case_a_home/installer-args"
run_bootstrap "$case_a_home" "$case_a_home/uninstall-output" --uninstall --dry-run
printf '%s\n' '--uninstall' '--dry-run' > "$case_a_home/expected-uninstall-args"
assert_files_equal "$case_a_home/expected-uninstall-args" "$case_a_home/installer-args"

# C: una actualización remota se aplica exclusivamente por fast-forward.
printf 'update\n' > "$SEED_REPOSITORY/update.txt"
git_test -C "$SEED_REPOSITORY" add update.txt
git_test -C "$SEED_REPOSITORY" -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.invalid' commit -qm 'fixture update'
updated_commit="$(git_test -C "$SEED_REPOSITORY" rev-parse HEAD)"
git_test -C "$SEED_REPOSITORY" push -q origin main
run_bootstrap "$case_a_home" "$case_a_home/update-output" --profile server --yes
[[ "$(git_test -C "$case_a_repo" rev-parse HEAD)" == "$updated_commit" ]] ||
    fail 'no se aplicó la actualización fast-forward'

# D: los cambios locales abortan sin modificarse y sin ejecutar install.sh.
case_d_home="$TEST_ROOT/case-d-home"
case_d_repo="$TEST_ROOT/case-d-repo"
mkdir -p "$case_d_home"
run_bootstrap_in "$case_d_home" "$case_d_repo" "$case_d_home/initial-output" --profile server --yes
printf 'local change\n' >> "$case_d_repo/bootstrap.sh"
local_digest="$(cksum "$case_d_repo/bootstrap.sh")"
printf 'sentinel\n' > "$case_d_home/installer-args"
expect_bootstrap_failure "$case_d_home" "$case_d_repo" "$case_d_home/error-output" --profile server --yes
[[ "$(cksum "$case_d_repo/bootstrap.sh")" == "$local_digest" ]] ||
    fail 'se modificaron los cambios locales'
assert_file_line "$case_d_home/installer-args" 'sentinel'
assert_contains "$case_d_home/error-output" 'se conservan intactos'

# E: un directorio que no es repo se conserva y provoca un error.
case_e_home="$TEST_ROOT/case-e-home"
case_e_repo="$TEST_ROOT/case-e-repo"
mkdir -p "$case_e_home" "$case_e_repo"
printf 'keep\n' > "$case_e_repo/marker"
expect_bootstrap_failure "$case_e_home" "$case_e_repo" "$case_e_home/output" --profile server --yes
assert_file_line "$case_e_repo/marker" 'keep'
assert_contains "$case_e_home/output" 'no es el repositorio Git esperado'

# F: un origin distinto se rechaza sin alterar el repositorio.
case_f_home="$TEST_ROOT/case-f-home"
case_f_repo="$TEST_ROOT/case-f-repo"
mkdir -p "$case_f_home" "$case_f_repo"
git_test -C "$case_f_repo" init -q -b main
printf 'foreign\n' > "$case_f_repo/marker"
git_test -C "$case_f_repo" add marker
git_test -C "$case_f_repo" -c user.name='Bootstrap Test' \
    -c user.email='bootstrap@example.invalid' commit -qm 'foreign repo'
git_test -C "$case_f_repo" remote add origin 'https://github.com/example/foreign.git'
foreign_head="$(git_test -C "$case_f_repo" rev-parse HEAD)"
expect_bootstrap_failure "$case_f_home" "$case_f_repo" "$case_f_home/output" --profile server --yes
[[ "$(git_test -C "$case_f_repo" rev-parse HEAD)" == "$foreign_head" ]] ||
    fail 'se modificó el repositorio con origin distinto'
assert_file_line "$case_f_repo/marker" 'foreign'

# I: un tag queda en detached HEAD y --ref no llega al instalador.
case_i_home="$TEST_ROOT/case-i-home"
case_i_repo="$TEST_ROOT/case-i-repo"
mkdir -p "$case_i_home"
run_bootstrap_in "$case_i_home" "$case_i_repo" "$case_i_home/tag-output" \
    --ref v1.1.0 --profile server --yes
[[ "$(git_test -C "$case_i_repo" rev-parse HEAD)" == "$initial_commit" ]] ||
    fail 'el tag no seleccionó el commit esperado'
if git_test -C "$case_i_repo" symbolic-ref -q HEAD >/dev/null; then
    fail 'el tag no quedó en detached HEAD'
fi
if command grep -Fxq -- '--ref' "$case_i_home/installer-args"; then
    fail '--ref se reenvió incorrectamente al instalador'
fi

# J: desde el tag se puede volver limpiamente a main.
run_bootstrap_in "$case_i_home" "$case_i_repo" "$case_i_home/main-output" \
    --ref main --profile server --yes
[[ "$(git_test -C "$case_i_repo" symbolic-ref --short HEAD)" == 'main' ]] ||
    fail 'no se volvió de detached HEAD a main'
[[ "$(git_test -C "$case_i_repo" rev-parse HEAD)" == "$updated_commit" ]] ||
    fail 'main no quedó actualizado al volver desde el tag'

# K: DOTFILES_DIR permite elegir otra ruta permanente absoluta.
case_k_home="$TEST_ROOT/case-k-home"
case_k_repo="$TEST_ROOT/custom/data/permanent-dotfiles"
mkdir -p "$case_k_home"
run_bootstrap_in "$case_k_home" "$case_k_repo" "$case_k_home/output" --profile server --yes
[[ -d "$case_k_repo/.git" ]] || fail 'DOTFILES_DIR personalizado no se respetó'

# L: install.sh resuelve su raíz fuera de ~/dotfiles.
case_l_home="$TEST_ROOT/case-l-home"
case_l_repo="$TEST_ROOT/unrelated/location/repository"
mkdir -p "$case_l_home" "$case_l_repo/scripts"
cp "$ROOT_DIR/install.sh" "$case_l_repo/install.sh"
cp "$ROOT_DIR/scripts/lib.sh" "$case_l_repo/scripts/lib.sh"
cp "$ROOT_DIR/scripts/zsh_components.sh" "$case_l_repo/scripts/zsh_components.sh"
cp "$ROOT_DIR/scripts/common.sh" "$case_l_repo/scripts/common.sh"
cp "$ROOT_DIR/scripts/state.sh" "$case_l_repo/scripts/state.sh"
HOME="$case_l_home" bash "$case_l_repo/install.sh" --help > "$case_l_home/output"
assert_contains "$case_l_home/output" 'Uso:'

# M: simula Git ausente y Fedora; los dobles no instalan nada en la máquina.
case_m_home="$TEST_ROOT/case-m-home"
case_m_repo="$TEST_ROOT/case-m-repo"
fake_bin="$TEST_ROOT/fake-bin"
git_ready="$TEST_ROOT/git-ready"
manager_log="$TEST_ROOT/manager-log"
mkdir -p "$case_m_home" "$fake_bin"
# Las expansiones pertenecen a los ejecutables ficticios.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ ! -e "$BOOTSTRAP_TEST_GIT_READY" ]]; then exit 127; fi' \
    'exec "$BOOTSTRAP_TEST_REAL_GIT" "$@"' \
    > "$fake_bin/git"
printf '%s\n' '#!/usr/bin/env bash' 'printf "Linux\n"' > "$fake_bin/uname"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "dnf %s\n" "$*" > "$BOOTSTRAP_TEST_MANAGER_LOG"' \
    'touch "$BOOTSTRAP_TEST_GIT_READY"' \
    > "$fake_bin/dnf"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" > "$BOOTSTRAP_TEST_MANAGER_LOG"' \
    'touch "$BOOTSTRAP_TEST_GIT_READY"' \
    > "$fake_bin/sudo"
chmod +x "$fake_bin/git" "$fake_bin/uname" "$fake_bin/dnf" "$fake_bin/sudo"
HOME="$case_m_home" DOTFILES_DIR="$case_m_repo" PATH="$fake_bin:$PATH" \
    GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 \
    BOOTSTRAP_TEST_GIT_READY="$git_ready" BOOTSTRAP_TEST_REAL_GIT="$REAL_GIT" \
    BOOTSTRAP_TEST_MANAGER_LOG="$manager_log" \
    BOOTSTRAP_TEST_ARGS_FILE="$case_m_home/installer-args" \
    BOOTSTRAP_TEST_ROOT_FILE="$case_m_home/installer-root" \
    bash -s -- --profile server --yes < "$ROOT_DIR/bootstrap.sh" > "$case_m_home/output" 2>&1
assert_contains "$manager_log" 'dnf install -y git'
[[ -d "$case_m_repo/.git" ]] || fail 'el bootstrap no continuó tras obtener Git'

printf 'OK: bootstrap remoto seguro e idempotente\n'
