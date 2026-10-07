#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
bin="$TEST_ROOT/bin"
mkdir -p "$bin"
# An isolated PATH makes missing dependencies reproducible on any host.
for name in bash dirname uname hostname git stow zsh jq awk cat chmod cksum cmp cp cut date find grep head id ln mkdir mktemp mv readlink rm rmdir sed sha256sum sort stat tail tar tr wc touch; do
  ln -s "$(command -v "$name")" "$bin/$name"
done
export FORBIDDEN_LOG="$TEST_ROOT/forbidden.log"
for name in sudo su chsh apt-get brew; do
  cat > "$bin/$name" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$FORBIDDEN_LOG"
exit 99
MOCK
  chmod +x "$bin/$name"
done
# Clone real, tiny local Git fixtures, with the expected upstream origins.
REAL_GIT="$(command -v git)"
export REAL_GIT
rm "$bin/git"
cat > "$bin/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" != clone ]]; then exec "$REAL_GIT" "$@"; fi
url="$3"; dest="$4"
case "$url" in
  */ohmyzsh/*) marker=oh-my-zsh.sh ;;
  */powerlevel10k.git) marker=powerlevel10k.zsh-theme ;;
  */zsh-autosuggestions.git) marker=zsh-autosuggestions.zsh ;;
  */zsh-syntax-highlighting.git) marker=zsh-syntax-highlighting.zsh ;;
  */zsh-history-substring-search.git) marker=zsh-history-substring-search.zsh ;;
  *) exit 99 ;;
esac
mkdir -p "$dest"
"$REAL_GIT" -C "$dest" init -q
touch "$dest/$marker"
"$REAL_GIT" -C "$dest" add .
"$REAL_GIT" -C "$dest" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
"$REAL_GIT" -C "$dest" remote add origin "$url"
MOCK
chmod +x "$bin/git"
run_install() {
  HOME="$home" XDG_STATE_HOME="$home/.state" PATH="$bin" \
    DOTFILES_LOGIN_SHELL=/bin/bash DOTFILES_SKIP_FONT=1 \
    GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    /bin/bash "$ROOT_DIR/install.sh" "$@"
}
for dependency in git stow zsh jq; do
  home="$TEST_ROOT/missing-$dependency"
  mkdir "$home"
  printf 'original\n' > "$home/.zshrc"
  mv "$bin/$dependency" "$TEST_ROOT/absent-$dependency"
  if run_install --profile server --yes --user-only > "$TEST_ROOT/missing.out" 2>&1; then fail "aceptó ausencia de $dependency"; fi
  grep -Fq "  - $dependency" "$TEST_ROOT/missing.out" || fail "no identificó $dependency"
  [[ "$(find "$home" -mindepth 1 | wc -l)" -eq 1 && "$(cat "$home/.zshrc")" == original ]] || fail 'preflight modificó HOME'
  if HOME="$home" PATH="$bin" /bin/bash "$ROOT_DIR/bootstrap.sh" --profile server --yes --user-only > "$TEST_ROOT/bootstrap-missing.out" 2>&1; then fail 'bootstrap aceptó dependencia ausente'; fi
  grep -Fq "  - $dependency" "$TEST_ROOT/bootstrap-missing.out" || fail 'bootstrap no identificó dependencia'
  [[ ! -e "$home/.local" ]] || fail 'bootstrap creó el directorio de clonación'
  mv "$TEST_ROOT/absent-$dependency" "$bin/$dependency"
done
[[ ! -e "$FORBIDDEN_LOG" ]] || fail 'preflight ejecutó privilegios'

# Normal mode must fail authentication BEFORE creating any state or changing HOME.
home="$TEST_ROOT/normal"
mkdir "$home"
# Force a non-root identity even when the suite runs as root.
rm "$bin/id"
cat > "$bin/id" <<'MOCK'
#!/usr/bin/env bash
case "$1" in -u) echo 1000;; -un) echo test-user;; *) exit 99;; esac
MOCK
chmod +x "$bin/id"
if run_install --profile server --yes > "$TEST_ROOT/normal.out" 2>&1; then fail 'sudo fallido aceptado'; fi
[[ -z "$(find "$home" -mindepth 1 -print)" ]] || fail 'sudo fallido dejó baseline o cambios'
grep -Fxq 'sudo -v' "$FORBIDDEN_LOG" || fail 'normal no validó sudo'
rm "$FORBIDDEN_LOG"

for profile in server personal work; do
  home="$TEST_ROOT/$profile"
  mkdir "$home"
  if [[ "$profile" == server ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/lsd"
    chmod +x "$bin/lsd"
  elif [[ "$profile" == personal ]]; then
    rm -f "$bin/lsd"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/eza"
    chmod +x "$bin/eza"
  else
    rm -f "$bin/lsd" "$bin/eza"
  fi
  # Debian command aliases must be optional and reversible.
  for name in fdfind batcat; do printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/$name"; chmod +x "$bin/$name"; done
  run_install --profile "$profile" --yes --user-only > "$TEST_ROOT/$profile.out" 2>&1 || { cat "$TEST_ROOT/$profile.out"; fail "$profile installation"; }
  [[ -L "$home/.zshrc" && -L "$home/.gitconfig" ]] || fail 'Stow incompleto'
  [[ -f "$home/.oh-my-zsh/oh-my-zsh.sh" && -f "$home/.config/dotfiles/zsh-components.zsh" ]] || fail 'componentes Zsh incompletos'
  [[ -L "$home/.local/bin/fd" && -L "$home/.local/bin/bat" ]] || fail 'faltan alias Debian'
  grep -Fq 'Opcional ausente: fzf' "$TEST_ROOT/$profile.out" || fail 'no informa opcionales'
  if [[ "$profile" != work ]]; then
    if grep -Fq 'herramienta de listado mejorado' "$TEST_ROOT/$profile.out"; then fail 'eza o lsd disponibles generaron aviso de listado'; fi
  else
    grep -Fq 'herramienta de listado mejorado' "$TEST_ROOT/$profile.out" || fail 'no avisó de la ausencia de eza y lsd'
  fi
  grep -Fq 'Zsh no es el shell de login actual' "$TEST_ROOT/$profile.out" || fail 'no informa shell'
  cycle="$home/.state/dotfiles/cycles/$(cat "$home/.state/dotfiles/active")"
  [[ "$(wc -l < "$cycle/packages.tsv")" -eq 1 ]] || fail 'atribuyó paquetes de sistema'
  run_install --profile "$profile" --yes --user-only > "$TEST_ROOT/repeat.out" 2>&1
  run_install --uninstall --yes > "$TEST_ROOT/restore.out" 2>&1
  [[ ! -L "$home/.local/bin/fd" && ! -L "$home/.local/bin/bat" ]] || fail 'rollback no retiró alias'
  [[ ! -e "$FORBIDDEN_LOG" ]] || fail 'user-only/rollback ejecutó privilegios o paquetes'
done

# Both helpers must abort, including when root or sudo was already validated.
for helper in run_privileged validate_sudo_once; do
  if (PATH="$bin"; source "$ROOT_DIR/scripts/lib.sh"; USER_ONLY=1; SUDO_VALIDATED=1; is_root_user() { return 0; }; "$helper" touch "$TEST_ROOT/unsafe") > "$TEST_ROOT/guard.out" 2>&1; then fail 'guard no abortó'; fi
  grep -Fq 'Error interno' "$TEST_ROOT/guard.out" || fail 'guard sin diagnóstico'
done
[[ ! -e "$TEST_ROOT/unsafe" && ! -e "$FORBIDDEN_LOG" ]] || fail 'guard ejecutó comando'
# An existing alias target (even a dangling symlink) is never overwritten.
(
  export HOME="$TEST_ROOT/alias-existing" PATH="$bin"
  mkdir -p "$HOME/.local/bin"
  printf 'keep\n' > "$HOME/.local/bin/fd"
  ln -s /missing/user-target "$HOME/.local/bin/bat"
  source "$ROOT_DIR/scripts/lib.sh"
  source "$ROOT_DIR/scripts/state.sh"
  source "$ROOT_DIR/scripts/common.sh"
  install_user_command_aliases
  [[ "$(cat "$HOME/.local/bin/fd")" == keep && "$(readlink "$HOME/.local/bin/bat")" == /missing/user-target ]] || fail 'sobrescribió un alias existente'
  USER_ONLY=1
  DOTFILES_OS=linux
  DOTFILES_LOGIN_SHELL=/usr/bin/zsh
  ensure_zsh_shell > "$TEST_ROOT/already-zsh.out"
  grep -Fq 'Zsh ya es el shell de login' "$TEST_ROOT/already-zsh.out" || fail 'no reconoció login Zsh'
)
# The unavoidable standalone preflight copy must stay identical.
sed -n '/^validate_user_only_dependencies() {/,/^}/p' "$ROOT_DIR/bootstrap.sh" > "$TEST_ROOT/bootstrap-preflight"
sed -n '/^validate_user_only_dependencies() {/,/^}/p' "$ROOT_DIR/scripts/lib.sh" > "$TEST_ROOT/installer-preflight"
cmp "$TEST_ROOT/bootstrap-preflight" "$TEST_ROOT/installer-preflight" || fail 'preflight duplicado divergente'
printf 'OK: user-only, dependencias, perfiles, rollback, alias y protección de privilegios\n'
