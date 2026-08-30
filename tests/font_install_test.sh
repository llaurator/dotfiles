#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$HOME" "$FAKE_BIN" "$TEST_ROOT/cycle"
PATH="$FAKE_BIN:$PATH"
export HOME PATH

source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/state.sh"
source "$ROOT_DIR/scripts/common.sh"

ACTIVE_CYCLE_DIR="$TEST_ROOT/cycle"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
profile_uses_nerd_font personal || fail 'personal no seleccionó la fuente'
profile_uses_nerd_font work || fail 'work no seleccionó la fuente'
if profile_uses_nerd_font server; then fail 'server seleccionó la fuente'; fi

printf 'relative_path\tbefore_fingerprint\tinstalled_fingerprint\n' > "$ACTIVE_CYCLE_DIR/fonts.tsv"
BASELINE_MODE=active
BASELINE_FORMAT=2
DOTFILES_OS=linux

# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'for ((i=1;i<=$#;i++)); do [[ "${!i}" == -o ]] && { j=$((i+1)); : > "${!j}"; exit; }; done' > "$FAKE_BIN/curl"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == -tq ]] && exit 0' '[[ "$1" == -jp ]] && { printf "font:%s\n" "$3"; exit; }' 'exit 1' > "$FAKE_BIN/unzip"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$HOME/fc-cache.log"' > "$FAKE_BIN/fc-cache"
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/unzip" "$FAKE_BIN/fc-cache"

install_nerd_font > "$TEST_ROOT/install.out"
for style in Regular Bold Italic BoldItalic; do [[ -s "$HOME/.local/share/fonts/MesloLGSNerdFont-$style.ttf" ]] || fail "falta $style"; done
[[ "$(wc -l < "$ACTIVE_CYCLE_DIR/fonts.tsv" | tr -d ' ')" == 5 ]] || fail 'tracking de fuentes incompleto'

before="$(cksum "$ACTIVE_CYCLE_DIR/fonts.tsv")"
install_nerd_font > "$TEST_ROOT/reinstall.out"
[[ "$(cksum "$ACTIVE_CYCLE_DIR/fonts.tsv")" == "$before" ]] || fail 'segunda instalación duplicó tracking'

printf 'cambio del usuario\n' > "$HOME/.local/share/fonts/MesloLGSNerdFont-Italic.ttf"
remove_cycle_fonts
[[ -f "$HOME/.local/share/fonts/MesloLGSNerdFont-Italic.ttf" ]] || fail 'rollback borró una fuente modificada'
for style in Regular Bold BoldItalic; do [[ ! -e "$HOME/.local/share/fonts/MesloLGSNerdFont-$style.ttf" ]] || fail "rollback conservó $style intacta"; done

# macOS: usa exactamente el cask mantenido y lo retira solo si lo introdujo el ciclo.
printf 'relative_path\tbefore_fingerprint\tinstalled_fingerprint\n' > "$ACTIVE_CYCLE_DIR/fonts.tsv"
DOTFILES_OS=macos
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ "$1 $2 $3" == "list --cask font-meslo-lg-nerd-font" ]]; then [[ -e "$HOME/brew-font-installed" ]]; exit; fi' \
  'if [[ "$1 $2 $3" == "install --cask font-meslo-lg-nerd-font" ]]; then : > "$HOME/brew-font-installed"; exit; fi' \
  'if [[ "$1 $2 $3" == "uninstall --cask font-meslo-lg-nerd-font" ]]; then rm -- "$HOME/brew-font-installed"; exit; fi' \
  'exit 1' > "$FAKE_BIN/brew"
chmod +x "$FAKE_BIN/brew"
install_nerd_font > "$TEST_ROOT/macos-install.out"
[[ -e "$HOME/brew-font-installed" ]] || fail 'macOS no instaló el cask esperado'
grep -Fq $'homebrew-cask:font-meslo-lg-nerd-font\tmissing\tinstalled_by_cycle' "$ACTIVE_CYCLE_DIR/fonts.tsv" || fail 'macOS no registró el cask'
remove_cycle_fonts
[[ ! -e "$HOME/brew-font-installed" ]] || fail 'macOS no retiró el cask atribuible'

printf 'OK: instalación y rollback seguro de MesloLGS Nerd Font\n'
