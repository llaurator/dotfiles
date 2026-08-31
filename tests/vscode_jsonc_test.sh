#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/common.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
DOTFILES_OS=linux
source_file="$TEST_ROOT/managed.json"
target_file="$TEST_ROOT/settings.json"
printf '{"managed":true,"[jsonc]":{"editor.defaultFormatter":"dotfiles"}}\n' > "$source_file"

# Comentarios, comas finales, URLs y secuencias parecidas a comentarios dentro
# de strings son JSONC válido y conservan tanto comentarios como claves ajenas.
printf '%s\n' \
  '{' \
  '  // keep line comment' \
  '  "url": "https://example.invalid/a//b",' \
  '  /* keep block comment */' \
  '  "text": "not /* a comment */",' \
  '  "managed": false,' \
  '  "nested": { "keep": true, },' \
  '}' > "$target_file"
merge_vscode_settings "$source_file" "$target_file"
grep -Fq '// keep line comment' "$target_file" || fail 'se perdió un comentario de línea'
grep -Fq '/* keep block comment */' "$target_file" || fail 'se perdió un comentario de bloque'
grep -Fq 'https://example.invalid/a//b' "$target_file" || fail 'una URL se interpretó como comentario'
normalized="$TEST_ROOT/normalized.json"
comments="$TEST_ROOT/comments.txt"
jsonc_to_json "$target_file" "$normalized" "$comments" || fail 'el JSONC fusionado no pudo normalizarse'
[[ "$(jq -r '.managed' "$normalized")" == true ]] || fail 'no se actualizó una clave gestionada existente'
[[ "$(jq -r '.nested.keep' "$normalized")" == true ]] || fail 'se perdió una clave ajena'
[[ "$(jq -r '.["[jsonc]"]."editor.defaultFormatter"' "$normalized")" == dotfiles ]] || fail 'no se insertó una clave gestionada ausente'
first_sum="$(sha256sum "$target_file" | awk '{print $1}')"
merge_vscode_settings "$source_file" "$target_file"
[[ "$(sha256sum "$target_file" | awk '{print $1}')" == "$first_sum" ]] || fail 'el merge JSONC no fue idempotente'

# JSONC realmente roto no se modifica.
printf '{ "broken": }\n' > "$target_file"
broken_sum="$(sha256sum "$target_file" | awk '{print $1}')"
if merge_vscode_settings "$source_file" "$target_file"; then fail 'se aceptó un JSONC roto'; fi
[[ "$(sha256sum "$target_file" | awk '{print $1}')" == "$broken_sum" ]] || fail 'se modificó un JSONC roto'

# Fixture representativo: solo se cambia el valor root y se añade una clave
# root ausente. Todo lo demás (incluida una cadena grande) coincide byte a byte.
large_value="data:image/png;base64,$(printf 'A%.0s' {1..8192})"
printf '%s\n' \
  '{' \
  '  // comentario inicial' \
  '  "editor.formatOnSave": false,' \
  '  "url": "https://example.invalid/path//kept",' \
  '  "[dart]": {' \
  '    "editor.formatOnSave": true,' \
  '  },' \
  '  /* comentario que debe permanecer aquí */' \
  "  \"markdownExtended.pdfHeaderTemplate\": \"$large_value\"," \
  '  "[python]": { "editor.defaultFormatter": "ms-python.black-formatter" },' \
  '  // "[java]": { "editor.defaultFormatter": "redhat.java" },' \
  '  "[java]": { "editor.defaultFormatter": "redhat.java" },' \
  '}' > "$target_file"
printf '%s\n' '{"editor.formatOnSave":true,"[jsonc]":{"editor.defaultFormatter":"dotfiles"}}' > "$source_file"
printf '%s\n' \
  '{' \
  '  // comentario inicial' \
  '  "editor.formatOnSave": true,' \
  '  "url": "https://example.invalid/path//kept",' \
  '  "[dart]": {' \
  '    "editor.formatOnSave": true,' \
  '  },' \
  '  /* comentario que debe permanecer aquí */' \
  "  \"markdownExtended.pdfHeaderTemplate\": \"$large_value\"," \
  '  "[python]": { "editor.defaultFormatter": "ms-python.black-formatter" },' \
  '  // "[java]": { "editor.defaultFormatter": "redhat.java" },' \
  '  "[java]": { "editor.defaultFormatter": "redhat.java" },' \
  '' \
  '  "[jsonc]": {"editor.defaultFormatter":"dotfiles"}' \
  '}' > "$TEST_ROOT/expected-settings.json"
merge_vscode_settings "$source_file" "$target_file"
cmp -s "$TEST_ROOT/expected-settings.json" "$target_file" || fail 'el merge textual modificó contenido no gestionado'
grep -Fq '    "editor.formatOnSave": true,' "$target_file" || fail 'se modificó el valor anidado de [dart]'
grep -Fq "$large_value" "$target_file" || fail 'se modificó la cadena base64 ajena'
advanced_sum="$(sha256sum "$target_file" | awk '{print $1}')"
merge_vscode_settings "$source_file" "$target_file"
[[ "$(sha256sum "$target_file" | awk '{print $1}')" == "$advanced_sum" ]] || fail 'el fixture realista no fue byte-idempotente'

printf 'OK: merge JSONC de VS Code conserva comentarios y configuración ajena\n'
