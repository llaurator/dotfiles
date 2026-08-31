#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/common.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  command grep -Fq -- "$2" "$1" || fail "no se encontró '$2' en $1"
}

create_git_home() {
  local test_home="$1"
  mkdir -p "$test_home/.config/git"
  # Git expande este ~ al resolver include.path; debe permanecer literal.
  # shellcheck disable=SC2088
  git config --file "$test_home/.gitconfig" include.path '~/.config/git/local.gitconfig'
}

read_calls=0
read_prompt=''
read_answer='n'
read() {
  local argument variable=''
  read_calls=$((read_calls + 1))
  read_prompt="$*"
  for argument in "$@"; do
    variable="$argument"
  done
  printf -v "$variable" '%s' "$read_answer"
}

configured_home="$TEST_ROOT/configured-home"
create_git_home "$configured_home"
git config --file "$configured_home/.config/git/local.gitconfig" user.name 'Test User'
git config --file "$configured_home/.config/git/local.gitconfig" user.email 'test@example.invalid'
HOME="$configured_home"
ASSUME_YES=0
read_calls=0
pushd "$configured_home" >/dev/null
configure_git_identity </dev/null >"$TEST_ROOT/configured.out"
popd >/dev/null
[[ "$read_calls" -eq 0 ]] || fail 'se intentó leer stdin con una identidad efectiva completa'
assert_contains "$TEST_ROOT/configured.out" 'Identidad Git ya configurada.'

interactive_home="$TEST_ROOT/interactive-home"
create_git_home "$interactive_home"
HOME="$interactive_home"
ASSUME_YES=0
read_calls=0
read_prompt=''
pushd "$interactive_home" >/dev/null
configure_git_identity </dev/null >"$TEST_ROOT/interactive.out"
popd >/dev/null
[[ "$read_calls" -eq 1 ]] || fail 'el modo interactivo no preguntó una vez por la identidad ausente'
[[ "$read_prompt" == *'No hay una identidad Git configurada.'* ]] || fail 'el prompt interactivo no fue el esperado'

assume_yes_home="$TEST_ROOT/assume-yes-home"
create_git_home "$assume_yes_home"
HOME="$assume_yes_home"
ASSUME_YES=1
read_calls=0
pushd "$assume_yes_home" >/dev/null
configure_git_identity </dev/null >"$TEST_ROOT/assume-yes.out"
popd >/dev/null
[[ "$read_calls" -eq 0 ]] || fail 'el modo --yes intentó leer stdin'
assert_contains "$TEST_ROOT/assume-yes.out" 'No hay una identidad Git completa; el modo --yes no la configura.'

# Solo un conflicto autorizado y respaldado puede aportar identidad al fichero
# local no versionado; no se imprime ningún valor durante la migración.
migrated_home="$TEST_ROOT/migrated-home"
create_git_home "$migrated_home"
migration_cycle="$TEST_ROOT/migration-cycle"
mkdir -p "$migration_cycle/files"
git config --file "$migration_cycle/files/.gitconfig" user.name 'Backup User'
git config --file "$migration_cycle/files/.gitconfig" user.email 'backup@example.invalid'
printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n.gitconfig\tfile\tfiles/.gitconfig\t600\tstow\tgit/.gitconfig\t-\n' > "$migration_cycle/manifest.tsv"
HOME="$migrated_home"
ACTIVE_CYCLE_DIR="$migration_cycle"
MANIFEST_FILE="$migration_cycle/manifest.tsv"
BASELINE_MODE=active
BACKUP_CONFLICTS=1
ASSUME_YES=0
read_calls=0
pushd "$migrated_home" >/dev/null
configure_git_identity </dev/null >"$TEST_ROOT/migrated.out"
popd >/dev/null
[[ "$read_calls" -eq 0 ]] || fail 'la identidad completa del backup abrió un prompt'
[[ "$(git config --file "$migrated_home/.config/git/local.gitconfig" --get user.name)" == 'Backup User' ]] || fail 'no se migró user.name desde el backup'
[[ "$(git config --file "$migrated_home/.config/git/local.gitconfig" --get user.email)" == 'backup@example.invalid' ]] || fail 'no se migró user.email desde el backup'

# Los valores locales existentes siempre prevalecen sobre el backup.
git config --file "$migrated_home/.config/git/local.gitconfig" user.name 'Local User'
git config --file "$migration_cycle/files/.gitconfig" user.name 'Other Backup User'
configure_git_identity </dev/null >"$TEST_ROOT/migrated-existing.out"
[[ "$(git config --file "$migrated_home/.config/git/local.gitconfig" --get user.name)" == 'Local User' ]] || fail 'se sobrescribió una identidad local existente'

printf 'OK: detección idempotente de identidad Git\n'
