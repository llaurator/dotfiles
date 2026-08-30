#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  local status=$?
  if (( status != 0 )); then
    printf 'Últimas salidas de prueba antes del fallo:\n' >&2
    find "$TEST_ROOT" -name '*.out' -exec tail -n 20 {} \; >&2 || true
  fi
  rm -rf "$TEST_ROOT"
  return "$status"
}
trap cleanup EXIT

FIXTURE_REPO="$TEST_ROOT/repository in another location"
FAKE_BIN="$TEST_ROOT/fake-bin"
STOW_LOG="$TEST_ROOT/stow.log"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  command grep -Fq -- "$2" "$1" || fail "no se encontró '$2' en $1"
}

assert_file_content() {
  [[ "$(< "$1")" == "$2" ]] || fail "contenido inesperado en $1"
}

active_cycle_dir() {
  local home="$1" cycle
  cycle="$(< "$home/.state/dotfiles/active")"
  printf '%s/.state/dotfiles/cycles/%s' "$home" "$cycle"
}

prepare_home() {
  local home="$1" repo
  mkdir -p "$home"
  for repo in \
    "$home/.oh-my-zsh" \
    "$home/.oh-my-zsh/custom/themes/powerlevel10k" \
    "$home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "$home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" \
    "$home/.oh-my-zsh/custom/plugins/zsh-history-substring-search"; do
    mkdir -p "$repo/.git"
  done
}

run_install() {
  local home="$1" output="$2"
  shift 2
  (
    cd "$home"
    HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$FAKE_BIN:$PATH" \
      SHELL="$FAKE_BIN/zsh" DOTFILES_LOGIN_SHELL=/bin/zsh DOTFILES_SKIP_FONT=1 STOW_TEST_LOG="$STOW_LOG" \
      GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      "$FIXTURE_REPO/install.sh" "$@"
  ) > "$output" 2>&1
}

run_install_with_input() {
  local home="$1" input="$2" output="$3"
  shift 3
  printf '%b' "$input" | (
    cd "$home"
    HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$FAKE_BIN:$PATH" \
      SHELL="$FAKE_BIN/zsh" DOTFILES_LOGIN_SHELL=/bin/zsh DOTFILES_SKIP_FONT=1 STOW_TEST_LOG="$STOW_LOG" \
      GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      "$FIXTURE_REPO/install.sh" "$@"
  ) > "$output" 2>&1
}

run_install_dynamic_shell() {
  local home="$1" output="$2"
  shift 2
  (
    cd "$home"
    HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$FAKE_BIN:$PATH" \
      SHELL="$FAKE_BIN/zsh" DOTFILES_SKIP_FONT=1 STOW_TEST_LOG="$STOW_LOG" \
      LOGIN_SHELL_FILE="${LOGIN_SHELL_FILE:-}" CHSH_FAILURE_FILE="${CHSH_FAILURE_FILE:-}" \
      PACKAGE_STATE_DIR="${PACKAGE_STATE_DIR:-}" PACKAGE_FAILURE_FILE="${PACKAGE_FAILURE_FILE:-}" \
      REMOVE_FAILURE_FILE="${REMOVE_FAILURE_FILE:-}" REMOVE_FAILURE_MATCH="${REMOVE_FAILURE_MATCH:-}" \
      GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      "$FIXTURE_REPO/install.sh" "$@"
  ) > "$output" 2>&1
}

expect_failure() {
  if "$@"; then fail 'la operación debía haber fallado'; fi
}

mkdir -p "$FIXTURE_REPO" "$FAKE_BIN"
cp -R "$ROOT_DIR/install.sh" "$ROOT_DIR/scripts" "$ROOT_DIR/zsh" "$ROOT_DIR/git" \
  "$ROOT_DIR/btop" "$ROOT_DIR/ssh" "$ROOT_DIR/vscode" "$FIXTURE_REPO/"

# Ningún gestor de paquetes real se ejecuta en la copia de prueba.
for platform_script in macos arch fedora debian; do
  printf '%s\n' '#!/usr/bin/env bash' 'get_system_packages() { SYSTEM_PACKAGES=(); }' 'install_system_packages() { :; }' \
    > "$FIXTURE_REPO/scripts/$platform_script.sh"
done

# Doble mínimo de Stow: solo crea/retira enlaces dentro del HOME temporal.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'mode=restow; directory=; target_root=; package=' \
  'for argument in "$@"; do' \
  '  case "$argument" in' \
  '    -D) mode=delete ;;' \
  '    --restow|--no-folding) ;;' \
  '    --dir=*) directory=${argument#--dir=} ;;' \
  '    --target=*) target_root=${argument#--target=} ;;' \
  '    *) package=$argument ;;' \
  '  esac' \
  'done' \
  'printf "%s\t%s\n" "$mode" "$package" >> "$STOW_TEST_LOG"' \
  'while IFS= read -r -d "" source; do' \
  '  relative=${source#"$directory/$package/"}' \
  '  target=$target_root/$relative' \
  '  if [[ "$mode" == delete ]]; then' \
  '    if [[ -L "$target" && "$target" -ef "$source" ]]; then rm -- "$target"; fi' \
  '  else' \
  '    mkdir -p "${target%/*}"' \
  '    if [[ -L "$target" && "$target" -ef "$source" ]]; then rm -- "$target"; fi' \
  '    [[ ! -e "$target" && ! -L "$target" ]] || exit 1' \
  '    ln -s "$source" "$target"' \
  '  fi' \
  'done < <(find "$directory/$package" -type f -print0)' \
  > "$FAKE_BIN/stow"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/zsh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/chsh"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${1:-}" == --list-extensions ]]; then exit 0; fi' \
  'printf "%s\n" "$*" >> "$STOW_TEST_LOG.code"' \
  > "$FAKE_BIN/code"
chmod +x "$FAKE_BIN/stow" "$FAKE_BIN/zsh" "$FAKE_BIN/chsh" "$FAKE_BIN/code"

# A, W e Y: primera instalación real desde una ruta arbitraria y baseline missing.
home_a="$TEST_ROOT/home-a"
prepare_home "$home_a"
run_install "$home_a" "$home_a/install.out" --profile server --yes
cycle_a="$(active_cycle_dir "$home_a")"
[[ -L "$home_a/.zshrc" && -L "$home_a/.gitconfig" ]] || fail 'Stow no desplegó los enlaces esperados'
assert_contains "$cycle_a/manifest.tsv" $'.zshrc\tmissing\t-\t-\tstow\tzsh/.zshrc'
assert_contains "$cycle_a/manifest.tsv" $'.gitconfig\tmissing\t-\t-\tstow\tgit/.gitconfig'
assert_contains "$cycle_a/metadata.tsv" $'format_version\t2'
assert_contains "$cycle_a/metadata.tsv" $'profile\tserver'

# D: una segunda instalación reutiliza el mismo ciclo y no modifica el manifest.
manifest_before="$(cksum "$cycle_a/manifest.tsv")"
cycle_id_before="$(< "$home_a/.state/dotfiles/active")"
run_install "$home_a" "$home_a/second-install.out" --profile server --yes
[[ "$(cksum "$cycle_a/manifest.tsv")" == "$manifest_before" ]] || fail 'la segunda instalación modificó la baseline'
[[ "$(< "$home_a/.state/dotfiles/active")" == "$cycle_id_before" ]] || fail 'la segunda instalación creó otro ciclo'

# E: dry-run muestra el plan sin tocar enlaces, perfil ni estado.
zsh_target_before="$(readlink "$home_a/.zshrc")"
profile_before="$(cksum "$home_a/.config/dotfiles/profile")"
status_before="$(< "$cycle_a/status")"
run_install "$home_a" "$home_a/dry-run.out" --uninstall --dry-run
[[ "$(readlink "$home_a/.zshrc")" == "$zsh_target_before" ]] || fail 'dry-run cambió .zshrc'
[[ "$(cksum "$home_a/.config/dotfiles/profile")" == "$profile_before" ]] || fail 'dry-run cambió el perfil'
[[ "$(< "$cycle_a/status")" == "$status_before" ]] || fail 'dry-run cambió el estado'
assert_contains "$home_a/dry-run.out" 'Dry-run: no se ha modificado ningún archivo.'

# F, G y O: uninstall retira lo gestionado y marca restored.
run_install "$home_a" "$home_a/uninstall.out" --uninstall --yes
[[ ! -e "$home_a/.zshrc" && ! -L "$home_a/.zshrc" ]] || fail 'no se retiró un enlace originalmente missing'
[[ ! -e "$home_a/.gitconfig" && ! -L "$home_a/.gitconfig" ]] || fail 'no se retiró .gitconfig'
[[ -d "$home_a/.oh-my-zsh" ]] || fail 'se eliminó una herramienta que debía conservarse'
assert_file_content "$cycle_a/status" 'restored'
assert_contains "$home_a/uninstall.out" 'La configuración y el entorno atribuible a este ciclo se han restaurado.'

# S: un segundo uninstall es idempotente.
run_install "$home_a" "$home_a/second-uninstall.out" --uninstall --yes
assert_contains "$home_a/second-uninstall.out" 'ya fue restaurado'

# T: reinstalar tras restore crea un ciclo nuevo.
run_install "$home_a" "$home_a/reinstall.out" --profile server --yes
[[ "$(< "$home_a/.state/dotfiles/active")" != "$cycle_id_before" ]] || fail 'la reinstalación reutilizó una baseline restaurada'

# B: conflictos existentes cancelan por defecto y solo se mueven con autorización explícita.
home_b="$TEST_ROOT/home-b"
prepare_home "$home_b"
printf 'original zsh\n' > "$home_b/.zshrc"
printf 'original git\n' > "$home_b/.gitconfig"
expect_failure run_install "$home_b" "$home_b/conservative.out" --profile server --yes
assert_file_content "$home_b/.zshrc" 'original zsh'
[[ ! -e "$home_b/.state/dotfiles/active" ]] || fail '--yes creó una baseline antes de abortar el conflicto'
expect_failure run_install_with_input "$home_b" '\n\n' "$home_b/interactive-cancel.out" --profile server
assert_file_content "$home_b/.gitconfig" 'original git'
run_install "$home_b" "$home_b/backup-install.out" --profile server --yes --backup-conflicts
cycle_b="$(active_cycle_dir "$home_b")"
assert_file_content "$cycle_b/files/.zshrc" 'original zsh'
assert_file_content "$cycle_b/files/.gitconfig" 'original git'
run_install "$home_b" "$home_b/restore.out" --uninstall --yes
assert_file_content "$home_b/.zshrc" 'original zsh'
assert_file_content "$home_b/.gitconfig" 'original git'

# C: un symlink previo se copia como symlink y se restaura sin dereferenciarlo.
home_c="$TEST_ROOT/home-c"
prepare_home "$home_c"
printf 'target\n' > "$home_c/original-zshrc"
ln -s "$home_c/original-zshrc" "$home_c/.zshrc"
run_install "$home_c" "$home_c/install.out" --profile server --yes --backup-conflicts
cycle_c="$(active_cycle_dir "$home_c")"
[[ -L "$cycle_c/files/.zshrc" ]] || fail 'la baseline dereferenció el symlink previo'
[[ "$(readlink "$cycle_c/files/.zshrc")" == "$home_c/original-zshrc" ]] || fail 'cambió el destino del symlink respaldado'
expect_failure run_install_with_input "$home_c" '\n' "$home_c/cancel-uninstall.out" --uninstall
[[ -L "$home_c/.zshrc" && "$(readlink "$home_c/.zshrc")" != "$home_c/original-zshrc" ]] ||
  fail 'Enter confirmó una restauración que debía usar default NO'
run_install "$home_c" "$home_c/uninstall.out" --uninstall --yes
[[ -L "$home_c/.zshrc" && "$(readlink "$home_c/.zshrc")" == "$home_c/original-zshrc" ]] || fail 'no se restauró el symlink previo'

# Un directorio situado exactamente en una ruta gestionada conserva tipo y contenido.
home_directory="$TEST_ROOT/home-directory"
prepare_home "$home_directory"
mkdir -p "$home_directory/.zshrc"
printf 'nested\n' > "$home_directory/.zshrc/local-file"
run_install "$home_directory" "$home_directory/install.out" --profile server --yes --backup-conflicts
cycle_directory="$(active_cycle_dir "$home_directory")"
assert_contains "$cycle_directory/manifest.tsv" $'.zshrc\tdirectory\tfiles/.zshrc'
run_install "$home_directory" "$home_directory/uninstall.out" --uninstall --yes
assert_file_content "$home_directory/.zshrc/local-file" 'nested'

# H: un archivo creado por el usuario sobre una ruta originalmente missing nunca se borra.
home_h="$TEST_ROOT/home-h"
prepare_home "$home_h"
run_install "$home_h" "$home_h/install.out" --profile server --yes
rm -- "$home_h/.zshrc"
printf 'user content\n' > "$home_h/.zshrc"
expect_failure run_install "$home_h" "$home_h/uninstall.out" --uninstall --yes
assert_file_content "$home_h/.zshrc" 'user content'

# I: un enlace gestionado que ahora apunta a otro sitio también bloquea todo el restore.
rm -- "$home_h/.gitconfig"
printf 'foreign\n' > "$home_h/foreign-gitconfig"
ln -s "$home_h/foreign-gitconfig" "$home_h/.gitconfig"
expect_failure run_install "$home_h" "$home_h/foreign-link.out" --uninstall --yes
[[ "$(readlink "$home_h/.gitconfig")" == "$home_h/foreign-gitconfig" ]] || fail 'se alteró el symlink externo'

# J, K, M y N: SSH local, identidad previa, VS Code e historiales vuelven intactos.
home_j="$TEST_ROOT/home-j"
prepare_home "$home_j"
mkdir -p "$home_j/.ssh/config.d" "$home_j/.config/git"
printf 'Host internal\n' > "$home_j/.ssh/config.d/local.conf"
printf '[user]\n\tname = Previous\n\temail = previous@example.invalid\n' > "$home_j/.config/git/local.gitconfig"
printf 'bash history\n' > "$home_j/.bash_history"
printf 'zsh history\n' > "$home_j/.zsh_history"
if [[ "$(uname -s)" == Darwin ]]; then
  vscode_settings="$home_j/Library/Application Support/Code/User/settings.json"
else
  vscode_settings="$home_j/.config/Code/User/settings.json"
fi
vscode_locale="${vscode_settings%/*}/locale.json"
mkdir -p "${vscode_settings%/*}"
printf '{"local":true}\n' > "$vscode_settings"
printf '{"locale":"fr","preserve":true}\n' > "$vscode_locale"
run_install "$home_j" "$home_j/install.out" --profile personal --yes
command grep -Fq '"local": true' "$vscode_settings" || fail 'VS Code perdió settings locales durante el merge'
command grep -Fq '"locale": "es"' "$vscode_locale" || fail 'VS Code no activó el locale español'
command grep -Fq '"preserve": true' "$vscode_locale" || fail 'VS Code perdió configuración previa de locale.json'
extensions_log_before="$(cksum "$STOW_LOG.code")"
run_install "$home_j" "$home_j/uninstall.out" --uninstall --yes
assert_file_content "$home_j/.ssh/config.d/local.conf" 'Host internal'
assert_contains "$home_j/.config/git/local.gitconfig" 'name = Previous'
assert_file_content "$vscode_settings" '{"local":true}'
assert_file_content "$vscode_locale" '{"locale":"fr","preserve":true}'
assert_file_content "$home_j/.bash_history" 'bash history'
assert_file_content "$home_j/.zsh_history" 'zsh history'
[[ "$(cksum "$STOW_LOG.code")" == "$extensions_log_before" ]] || fail 'uninstall modificó extensiones de VS Code'

# L: una identidad creada por este ciclo se retira si continúa sin cambios.
home_l="$TEST_ROOT/home-l"
prepare_home "$home_l"
run_install_with_input "$home_l" '\ns\nTest User\ntest@example.invalid\n' "$home_l/install.out" --profile server
[[ -f "$home_l/.config/git/local.gitconfig" ]] || fail 'no se creó la identidad Git local'
run_install "$home_l" "$home_l/uninstall.out" --uninstall --yes
[[ ! -e "$home_l/.config/git/local.gitconfig" ]] || fail 'no se retiró la identidad creada por la instalación'

# P: una instalación antigua no fabrica baseline; status lo indica y uninstall solo retira enlaces.
home_p="$TEST_ROOT/home-p"
prepare_home "$home_p"
HOME="$home_p" STOW_TEST_LOG="$STOW_LOG" "$FAKE_BIN/stow" --restow --no-folding \
  --dir="$FIXTURE_REPO" --target="$home_p" zsh
run_install "$home_p" "$home_p/status.out" --status
assert_contains "$home_p/status.out" 'Baseline:   no disponible'
assert_contains "$home_p/status.out" 'Installed:  yes'
[[ ! -e "$home_p/.state/dotfiles" ]] || fail 'status fabricó estado para instalación antigua'
run_install "$home_p" "$home_p/uninstall.out" --uninstall --yes
[[ ! -L "$home_p/.zshrc" ]] || fail 'uninstall legacy no retiró el enlace verificable'

# Q: un manifest corrupto aborta antes de retirar enlaces.
home_q="$TEST_ROOT/home-q"
prepare_home "$home_q"
run_install "$home_q" "$home_q/install.out" --profile server --yes
cycle_q="$(active_cycle_dir "$home_q")"
printf 'corrupt\n' >> "$cycle_q/manifest.tsv"
expect_failure run_install "$home_q" "$home_q/uninstall.out" --uninstall --yes
[[ -L "$home_q/.zshrc" ]] || fail 'manifest corrupto permitió modificar HOME'

# La huella del backup impide restaurar una copia alterada.
home_integrity="$TEST_ROOT/home-integrity"
prepare_home "$home_integrity"
printf 'original\n' > "$home_integrity/.zshrc"
run_install "$home_integrity" "$home_integrity/install.out" --profile server --yes --backup-conflicts
cycle_integrity="$(active_cycle_dir "$home_integrity")"
printf 'tampered\n' > "$cycle_integrity/files/.zshrc"
expect_failure run_install "$home_integrity" "$home_integrity/uninstall.out" --uninstall --yes
[[ -L "$home_integrity/.zshrc" ]] || fail 'un backup alterado permitió retirar configuración'

# R: path traversal se rechaza antes de tocar HOME.
home_r="$TEST_ROOT/home-r"
prepare_home "$home_r"
run_install "$home_r" "$home_r/install.out" --profile server --yes
cycle_r="$(active_cycle_dir "$home_r")"
printf '../escape\tmissing\t-\t-\tprofile\t-\t-\n' >> "$cycle_r/manifest.tsv"
printf 'outside\n' > "$TEST_ROOT/escape"
expect_failure run_install "$home_r" "$home_r/uninstall.out" --uninstall --yes
assert_file_content "$TEST_ROOT/escape" 'outside'
[[ -L "$home_r/.zshrc" ]] || fail 'path traversal permitió modificar HOME'

# Un componente padre que apunta fuera de HOME se rechaza antes del despliegue.
home_escape="$TEST_ROOT/home-escape"
outside_config="$TEST_ROOT/outside-config"
prepare_home "$home_escape"
mkdir -p "$outside_config"
printf 'outside\n' > "$outside_config/marker"
ln -s "$outside_config" "$home_escape/.config"
expect_failure run_install "$home_escape" "$home_escape/install.out" --profile server --yes
assert_file_content "$outside_config/marker" 'outside'
[[ ! -e "$home_escape/.state/dotfiles" ]] || fail 'se creó estado pese a escapar de HOME'

# U y V: status y el menú de estado son estrictamente de solo lectura.
home_u="$TEST_ROOT/home-u"
prepare_home "$home_u"
run_install "$home_u" "$home_u/status.out" --status
[[ ! -e "$home_u/.state/dotfiles" && ! -e "$home_u/.config" ]] || fail '--status modificó HOME'
run_install_with_input "$home_u" '4\n' "$home_u/menu.out"
assert_contains "$home_u/menu.out" 'Dotfiles status'
[[ ! -e "$home_u/.state/dotfiles" && ! -e "$home_u/.config" ]] || fail 'el menú de estado modificó HOME'
for menu_case in '1 install' '2 uninstall' '3 migrate' '4 status' '5 exit'; do
  choice="${menu_case%% *}"
  expected_action="${menu_case#* }"
  selected_action="$(printf '%s\n' "$choice" | bash -c \
    'source "$1"; choose_action' _ "$FIXTURE_REPO/scripts/lib.sh" 2>/dev/null)"
  [[ "$selected_action" == "$expected_action" ]] || fail "la opción $choice del menú no seleccionó $expected_action"
done

# HOME y XDG_STATE_HOME peligrosos se rechazan incluso en operaciones de solo lectura.
if env HOME=/ XDG_STATE_HOME="$TEST_ROOT/root-state" GIT_CONFIG_NOSYSTEM=1 \
  "$FIXTURE_REPO/install.sh" --status > "$TEST_ROOT/unsafe-home.out" 2>&1; then
  fail 'HOME=/ fue aceptado'
fi
if env HOME= XDG_STATE_HOME="$TEST_ROOT/empty-home-state" GIT_CONFIG_NOSYSTEM=1 \
  "$FIXTURE_REPO/install.sh" --status > "$TEST_ROOT/empty-home.out" 2>&1; then
  fail 'HOME vacío fue aceptado'
fi
if env HOME="$home_u" XDG_STATE_HOME=/ GIT_CONFIG_NOSYSTEM=1 \
  "$FIXTURE_REPO/install.sh" --status > "$TEST_ROOT/unsafe-state.out" 2>&1; then
  fail 'XDG_STATE_HOME=/ fue aceptado'
fi
HOME="$home_u" XDG_STATE_HOME='' GIT_CONFIG_NOSYSTEM=1 \
  "$FIXTURE_REPO/install.sh" --status > "$TEST_ROOT/empty-xdg-state.out"
[[ ! -e "$home_u/.local/state/dotfiles" ]] || fail 'status con XDG_STATE_HOME vacío modificó HOME'

# --keep-packages atraviesa el flujo completo sobre una fixture temporal sin consultar ni
# ejecutar el gestor, y conserva todos los paquetes registrados por el ciclo.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "dnf %s\n" "$*" >> "$KEEP_MANAGER_LOG"; exit 99' > "$FAKE_BIN/dnf"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "sudo %s\n" "$*" >> "$KEEP_MANAGER_LOG"; exit 99' > "$FAKE_BIN/sudo"
chmod +x "$FAKE_BIN/dnf" "$FAKE_BIN/sudo"
home_keep="$TEST_ROOT/home-keep-packages"
keep_manager_log="$TEST_ROOT/keep-manager.log"
prepare_home "$home_keep"
KEEP_MANAGER_LOG="$keep_manager_log" run_install "$home_keep" "$home_keep/install.out" --profile server --yes
cycle_keep="$(active_cycle_dir "$home_keep")"
printf 'A\tdnf\tinstalled_by_cycle\nB\tdnf\tinstalled_by_cycle\nC\tdnf\tinstalled_by_cycle\n' >> "$cycle_keep/packages.tsv"
printf 'packages remain\n' > "$home_keep/packages-remain.marker"
: > "$keep_manager_log"
KEEP_MANAGER_LOG="$keep_manager_log" run_install "$home_keep" "$home_keep/uninstall.out" --uninstall --keep-packages --yes
assert_file_content "$home_keep/packages-remain.marker" 'packages remain'
[[ ! -s "$keep_manager_log" ]] || fail '--keep-packages ejecutó un gestor real o ficticio'
assert_contains "$home_keep/uninstall.out" 'conservar A'
assert_contains "$home_keep/uninstall.out" 'conservar B'
assert_contains "$home_keep/uninstall.out" 'conservar C'

# Un rollback interrumpido se reanuda recurso a recurso. chsh se mantiene intacto:
# el doble solo permite reproducir un fallo externo y reflejar el shell resultante.
home_resume="$TEST_ROOT/home-resume"
prepare_home "$home_resume"
printf 'configuración original\n' > "$home_resume/.zshrc"
login_shell_file="$home_resume/login-shell"
printf '/usr/bin/zsh\n' > "$login_shell_file"
LOGIN_SHELL_FILE="$login_shell_file" run_install_dynamic_shell "$home_resume" "$home_resume/install.out" \
  --profile server --yes --backup-conflicts
cycle_resume="$(active_cycle_dir "$home_resume")"
sed -i $'s#^login_shell\t.*#login_shell\t/bin/bash\t/usr/bin/zsh#' "$cycle_resume/environment.tsv"

package_state_dir="$home_resume/package-state"
mkdir -p "$package_state_dir"
: > "$package_state_dir/zsh"
: > "$package_state_dir/tool-a"
printf 'zsh\tdnf\tinstalled_by_cycle\ntool-a\tdnf\tinstalled_by_cycle\n' >> "$cycle_resume/packages.tsv"

resume_upstream="$home_resume/.resume-upstream"
mkdir -p "$resume_upstream/.git"
printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\nResume upstream\t.resume-upstream\tno\thttps://github.com/example/resume.git\tcommit123\n' \
  > "$cycle_resume/upstream.tsv"
resume_font_rel='.local/share/fonts/MesloLGSNerdFont-Resume.ttf'
mkdir -p "$home_resume/.local/share/fonts"
printf 'font fixture\n' > "$home_resume/$resume_font_rel"
resume_font_fingerprint="$(
  HOME="$home_resume" PATH="$FAKE_BIN:$PATH" bash -c \
    'source "$1/scripts/lib.sh"; source "$1/scripts/state.sh"; path_fingerprint "$2"' _ \
    "$FIXTURE_REPO" "$home_resume/$resume_font_rel"
)"
printf '%s\tmissing\t%s\n' "$resume_font_rel" "$resume_font_fingerprint" >> "$cycle_resume/fonts.tsv"

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'shell=$(< "$LOGIN_SHELL_FILE")' \
  'printf "user:x:1000:1000::%s:%s\n" "$HOME" "$shell"' > "$FAKE_BIN/getent"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$HOME/chsh.log"' \
  'if [[ -n "${CHSH_FAILURE_FILE:-}" && -e "$CHSH_FAILURE_FILE" ]]; then exit 1; fi' \
  '[[ "$1" == -s && -n "${2:-}" ]] || exit 2' \
  'printf "%s\n" "$2" > "$LOGIN_SHELL_FILE"' > "$FAKE_BIN/chsh"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "$1" == -q && "$2" == -- ]] || exit 1' \
  '[[ -e "$PACKAGE_STATE_DIR/$3" ]]' > "$FAKE_BIN/rpm"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1" == remove && "$2" == --assumeno ]]; then exit 1; fi' \
  'if [[ -n "${PACKAGE_FAILURE_FILE:-}" && -e "$PACKAGE_FAILURE_FILE" ]]; then exit 9; fi' \
  'for argument in "$@"; do case "$argument" in zsh|tool-a) /usr/bin/rm -f -- "$PACKAGE_STATE_DIR/$argument";; esac; done' > "$FAKE_BIN/dnf"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == -v ]] && exit 0' 'exec "$@"' > "$FAKE_BIN/sudo"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'case "$*" in *"remote get-url origin"*) printf "https://github.com/example/resume.git\n";;' \
  '*"rev-parse HEAD"*) printf "commit123\n";;' \
  '*"status --porcelain"*) :;; *) exec /usr/bin/git "$@";; esac' > "$FAKE_BIN/git"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ -n "${REMOVE_FAILURE_FILE:-}" && -e "$REMOVE_FAILURE_FILE" && "$*" == *"$REMOVE_FAILURE_MATCH"* ]]; then exit 8; fi' \
  'exec /usr/bin/rm "$@"' > "$FAKE_BIN/rm"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BIN/fc-cache"
chmod +x "$FAKE_BIN/getent" "$FAKE_BIN/chsh" "$FAKE_BIN/rpm" "$FAKE_BIN/dnf" \
  "$FAKE_BIN/sudo" "$FAKE_BIN/git" "$FAKE_BIN/rm" "$FAKE_BIN/fc-cache"

chsh_failure_file="$home_resume/fail-chsh"
: > "$chsh_failure_file"
LOGIN_SHELL_FILE="$login_shell_file"; CHSH_FAILURE_FILE="$chsh_failure_file"; PACKAGE_STATE_DIR="$package_state_dir"
expect_failure run_install_dynamic_shell "$home_resume" "$home_resume/chsh-failure.out" --uninstall --yes
assert_file_content "$home_resume/.zshrc" 'configuración original'
[[ -e "$package_state_dir/zsh" && -e "$package_state_dir/tool-a" ]] || fail 'un fallo de chsh retiró paquetes'
[[ -d "$resume_upstream" && -f "$home_resume/$resume_font_rel" ]] || fail 'un fallo de chsh continuó con el entorno'
assert_contains "$cycle_resume/restore-journal.tsv" $'shell_restore\tlogin_shell\tstarted'

# Compatibilidad con la baseline real ya existente: sin el journal nuevo, los eventos
# removed/restored del restore.log y la huella del backup bastan para reconocer lo hecho.
/usr/bin/rm -- "$cycle_resume/restore-journal.tsv"
journal_before="$(cksum "$cycle_resume/restore.log")"
LOGIN_SHELL_FILE="$login_shell_file" CHSH_FAILURE_FILE="$chsh_failure_file" \
  PACKAGE_STATE_DIR="$package_state_dir" run_install_dynamic_shell "$home_resume" "$home_resume/partial-dry-run.out" --uninstall --dry-run
assert_contains "$home_resume/partial-dry-run.out" 'Hecho:      ~/.zshrc'
assert_contains "$home_resume/partial-dry-run.out" 'pendiente: /usr/bin/zsh → /bin/bash'
[[ "$(cksum "$cycle_resume/restore.log")" == "$journal_before" && ! -e "$cycle_resume/restore-journal.tsv" ]] ||
  fail 'el dry-run parcial modificó los checkpoints'
LOGIN_SHELL_FILE="$login_shell_file" PACKAGE_STATE_DIR="$package_state_dir" \
  run_install_dynamic_shell "$home_resume" "$home_resume/partial-status.out" --status
assert_contains "$home_resume/partial-status.out" 'Restore:    parcial / pendiente'

# Si el usuario cambia el archivo después de restaurarlo, el checkpoint no autoriza
# sobrescribirlo ni permite que continúe el rollback.
printf 'cambio posterior del usuario\n' > "$home_resume/.zshrc"
chsh_log_before="$(wc -l < "$home_resume/chsh.log" | tr -d ' ')"
expect_failure run_install_dynamic_shell "$home_resume" "$home_resume/user-change.out" --uninstall --yes
assert_file_content "$home_resume/.zshrc" 'cambio posterior del usuario'
[[ "$(wc -l < "$home_resume/chsh.log" | tr -d ' ')" == "$chsh_log_before" ]] || fail 'el conflicto posterior llegó a chsh'
printf 'configuración original\n' > "$home_resume/.zshrc"

# chsh tiene éxito al reintentar; a partir de ahí cada fallo posterior deja su acción
# started y las acciones completed no se repiten.
/usr/bin/rm -- "$chsh_failure_file"
CHSH_FAILURE_FILE=''
remove_failure_file="$home_resume/fail-remove"
: > "$remove_failure_file"
REMOVE_FAILURE_FILE="$remove_failure_file"; REMOVE_FAILURE_MATCH='.resume-upstream'; PACKAGE_FAILURE_FILE=''
expect_failure run_install_dynamic_shell "$home_resume" "$home_resume/upstream-failure.out" --uninstall --yes
assert_file_content "$login_shell_file" '/bin/bash'
[[ -e "$package_state_dir/zsh" && -e "$package_state_dir/tool-a" ]] || fail 'un fallo upstream retiró paquetes'
[[ -d "$resume_upstream" ]] || fail 'el fallo upstream no fue reproducible'

/usr/bin/rm -- "$remove_failure_file"
REMOVE_FAILURE_FILE=''; REMOVE_FAILURE_MATCH=''
package_failure_file="$home_resume/fail-packages"
: > "$package_failure_file"
PACKAGE_FAILURE_FILE="$package_failure_file"
expect_failure run_install_dynamic_shell "$home_resume" "$home_resume/package-failure.out" --uninstall --yes
[[ ! -e "$resume_upstream" ]] || fail 'el retry no completó upstream'
[[ -e "$package_state_dir/zsh" && -e "$package_state_dir/tool-a" ]] || fail 'el gestor ficticio fallido retiró paquetes'

/usr/bin/rm -- "$package_failure_file"
PACKAGE_FAILURE_FILE=''
: > "$remove_failure_file"
REMOVE_FAILURE_FILE="$remove_failure_file"; REMOVE_FAILURE_MATCH='MesloLGSNerdFont-Resume.ttf'
expect_failure run_install_dynamic_shell "$home_resume" "$home_resume/font-failure.out" --uninstall --yes
[[ ! -e "$package_state_dir/zsh" && ! -e "$package_state_dir/tool-a" ]] || fail 'el retry no completó paquetes'
[[ -f "$home_resume/$resume_font_rel" ]] || fail 'el fallo de fuente no fue reproducible'

/usr/bin/rm -- "$remove_failure_file"
REMOVE_FAILURE_FILE=''; REMOVE_FAILURE_MATCH=''
run_install_dynamic_shell "$home_resume" "$home_resume/resumed.out" --uninstall --yes
[[ ! -e "$home_resume/$resume_font_rel" ]] || fail 'el retry no completó la fuente'
assert_file_content "$cycle_resume/status" 'restored'
run_install_dynamic_shell "$home_resume" "$home_resume/idempotent.out" --uninstall --yes
assert_contains "$home_resume/idempotent.out" 'ya fue restaurado'

printf 'OK: instalación reversible, restauración y seguridad de baseline\n'
