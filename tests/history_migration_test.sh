#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

write_lines() {
  local target="$1"
  shift
  printf '%s\n' "$@" > "$target"
}

file_digest() {
  cksum "$1" | awk '{ print $1 ":" $2 }'
}

assert_contains() {
  command grep -Fq -- "$2" "$1" || fail "no se encontró '$2' en $1"
}

assert_not_contains() {
  if command grep -Fq -- "$2" "$1"; then
    fail "se encontró contenido sensible o inesperado en $1"
  fi
}

assert_history_command() {
  local history_file="$1" command="$2"
  awk '{ line=$0; sub(/^: [0-9][0-9]*:[0-9][0-9]*;/, "", line); print line }' "$history_file" |
    command grep -Fxq -- "$command" || fail "no se encontró el comando esperado en $history_file"
}

# A: crea un historial Zsh inexistente en el formato extendido usado por SHARE_HISTORY.
case_a="$TEST_ROOT/case-a"
mkdir -p "$case_a"
write_lines "$case_a/.bash_history" 'ls -la' 'git status' 'ls -la' ''
bash_digest="$(file_digest "$case_a/.bash_history")"
HOME="$case_a" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_a/output"
[[ "$(file_digest "$case_a/.bash_history")" == "$bash_digest" ]] || fail 'la migración modificó el historial Bash original'
assert_history_command "$case_a/.zsh_history" 'ls -la'
assert_history_command "$case_a/.zsh_history" 'git status'
command grep -Eq '^: [0-9]+:0;ls -la$' "$case_a/.zsh_history" || fail 'la entrada nueva no usa formato extendido Zsh'
[[ "$(awk '{ line=$0; sub(/^: [0-9][0-9]*:[0-9][0-9]*;/, "", line); if (line == "ls -la") count++ } END { print count + 0 }' "$case_a/.zsh_history")" -eq 1 ]] || fail 'se importó un duplicado del historial Bash'
[[ ! -e "$case_a/.zsh_history.pre-bash-migration" ]] || fail 'se creó backup sin historial Zsh previo'

# B: conserva el historial Zsh y añade únicamente comandos nuevos.
case_b="$TEST_ROOT/case-b"
mkdir -p "$case_b"
write_lines "$case_b/.zsh_history" ': 1700000000:2;echo existing' 'plain existing'
write_lines "$case_b/.bash_history" 'echo existing' 'plain existing' 'git log --oneline'
original_b="$(file_digest "$case_b/.zsh_history")"
HOME="$case_b" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_b/output"
assert_history_command "$case_b/.zsh_history" 'echo existing'
assert_history_command "$case_b/.zsh_history" 'plain existing'
assert_history_command "$case_b/.zsh_history" 'git log --oneline'
[[ "$(awk '{ line=$0; sub(/^: [0-9][0-9]*:[0-9][0-9]*;/, "", line); if (line == "plain existing") count++ } END { print count + 0 }' "$case_b/.zsh_history")" -eq 1 ]] || fail 'se duplicó una entrada Zsh en formato tradicional'
[[ "$(file_digest "$case_b/.zsh_history.pre-bash-migration")" == "$original_b" ]] || fail 'el backup no conserva el historial Zsh original'

# C: una segunda ejecución no añade duplicados ni modifica el historial.
before_second="$(file_digest "$case_b/.zsh_history")"
HOME="$case_b" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_b/second-output"
[[ "$(file_digest "$case_b/.zsh_history")" == "$before_second" ]] || fail 'la segunda migración modificó el historial'
[[ "$(awk '{ line=$0; sub(/^: [0-9][0-9]*:[0-9][0-9]*;/, "", line); if (line == "git log --oneline") count++ } END { print count + 0 }' "$case_b/.zsh_history")" -eq 1 ]] || fail 'se duplicó un comando migrado'

# D y E: ignora timestamps Bash, pero conserva comentarios reales que empiezan por #.
case_de="$TEST_ROOT/case-de"
mkdir -p "$case_de"
write_lines "$case_de/.bash_history" '#1234567890' '#123456789' 'pwd' '# esto es un comentario' '#1234'
HOME="$case_de" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_de/output"
assert_history_command "$case_de/.zsh_history" 'pwd'
assert_history_command "$case_de/.zsh_history" '# esto es un comentario'
assert_history_command "$case_de/.zsh_history" '#1234'
assert_not_contains "$case_de/.zsh_history" '#1234567890'
assert_not_contains "$case_de/.zsh_history" '#123456789'

# F: filtra patrones sensibles y nunca imprime sus valores.
case_f="$TEST_ROOT/case-f"
mkdir -p "$case_f"
private_key_marker='-----BEGIN OPENSSH '"PRIVATE"' KEY-----'
write_lines "$case_f/.bash_history" \
  'password=hunter2 command' \
  'passwd=do-not-print' \
  'token=secret-token-value' \
  'api_key=secret-api-key' \
  'apikey=another-api-key' \
  'secret=classified-value' \
  "curl -H 'Authorization: Bearer bearer-value' https://example.invalid" \
  'export GITHUB_TOKEN=exported-token-value' \
  "printf '%s' '$private_key_marker'" \
  'echo safe-command'
HOME="$case_f" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_f/output" 2>&1
assert_history_command "$case_f/.zsh_history" 'echo safe-command'
assert_contains "$case_f/output" 'Omitidas por posible secreto: 9'
assert_not_contains "$case_f/.zsh_history" 'hunter2'
for sensitive_value in hunter2 do-not-print secret-token-value secret-api-key another-api-key classified-value bearer-value exported-token-value "$private_key_marker"; do
  assert_not_contains "$case_f/output" "$sensitive_value"
done

# G: el backup se crea una sola vez y no se sobrescribe al importar más comandos.
case_g="$TEST_ROOT/case-g"
mkdir -p "$case_g"
write_lines "$case_g/.zsh_history" ': 1700000000:0;echo original'
write_lines "$case_g/.bash_history" 'echo first-import'
HOME="$case_g" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_g/first-output"
backup_digest="$(file_digest "$case_g/.zsh_history.pre-bash-migration")"
write_lines "$case_g/.bash_history" 'echo first-import' 'echo second-import'
HOME="$case_g" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_g/second-output"
[[ "$(file_digest "$case_g/.zsh_history.pre-bash-migration")" == "$backup_digest" ]] || fail 'el backup inicial fue sobrescrito'
assert_history_command "$case_g/.zsh_history" 'echo second-import'

# H: dry-run muestra estadísticas y no crea ni modifica historiales o backups.
case_h="$TEST_ROOT/case-h"
mkdir -p "$case_h"
write_lines "$case_h/.bash_history" 'echo preview-only'
write_lines "$case_h/.zsh_history" ': 1700000000:0;echo existing'
dry_before="$(file_digest "$case_h/.zsh_history")"
HOME="$case_h" "$ROOT_DIR/install.sh" --migrate-bash-history --dry-run > "$case_h/output"
[[ "$(file_digest "$case_h/.zsh_history")" == "$dry_before" ]] || fail 'dry-run modificó el historial Zsh'
[[ ! -e "$case_h/.zsh_history.pre-bash-migration" ]] || fail 'dry-run creó un backup'
assert_contains "$case_h/output" 'Nuevas para importar: 1'
assert_contains "$case_h/output" 'Dry-run: no se ha modificado ningún historial.'

# Sin historial Bash no se crea ningún archivo innecesario.
case_empty="$TEST_ROOT/case-empty"
mkdir -p "$case_empty"
HOME="$case_empty" "$ROOT_DIR/install.sh" --migrate-bash-history > "$case_empty/output"
[[ ! -e "$case_empty/.zsh_history" ]] || fail 'se creó historial Zsh sin historial Bash'
assert_contains "$case_empty/output" 'No hay historial Bash para migrar'

printf 'OK: migración idempotente de historial Bash a Zsh\n'
