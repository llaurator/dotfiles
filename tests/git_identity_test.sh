#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"
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

printf 'OK: detección idempotente de identidad Git\n'
