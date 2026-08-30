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
printf '%s\n' '#!/usr/bin/env bash' \
  'output= url=' \
  'while (( $# )); do case "$1" in -o) output=$2; shift 2;; *) url=$1; shift;; esac; done' \
  'if [[ -n "${FONT_CORRUPT_STYLE:-}" && "$url" == *"$FONT_CORRUPT_STYLE.ttf" ]]; then printf "corrupt\n" > "$output"; else printf "font:%s\n" "$url" > "$output"; fi' \
  'printf "%s\n" "$url" >> "$HOME/curl.log"' > "$FAKE_BIN/curl"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$HOME/fc-cache.log"' > "$FAKE_BIN/fc-cache"
# shellcheck disable=SC2016 # El doble consulta variables al ejecutarse.
printf '%s\n' '#!/usr/bin/env bash' '[[ "${FONTCONFIG_DISABLED:-0}" != 1 ]]' > "$FAKE_BIN/fc-list"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "${FONTCONFIG_DISABLED:-0}" != 1 ]] || exit 127' \
  'case "$*" in *"MesloLGS Nerd Font"*) family=${FONTCONFIG_NERD_FONT_FAMILY:-Otra Nerd Font};; *"MesloLGS NF"*) family=${FONTCONFIG_NF_FAMILY:-Otra Nerd Font};; *) exit 1;; esac' \
  'printf "%s\n" "$family"' > "$FAKE_BIN/fc-match"
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/fc-cache" "$FAKE_BIN/fc-list" "$FAKE_BIN/fc-match"

# Las descargas ficticias conservan el nombre de la variante en su contenido;
# este doble permite probar los hashes fijados sin incluir binarios TTF en el repo.
sha256_stream() {
  local content
  content="$(command cat)"
  case "$content" in
    *MesloLGSNerdFont-Regular.ttf) printf 'f3148b1e05c1dcf86785020d1d144524b9458deaab17505b88ecfe1694543214' ;;
    *MesloLGSNerdFont-Bold.ttf) printf '63ff060fbe6db68ee719137640217f28da72fb1b78c1c41f254451f3fca1f236' ;;
    *MesloLGSNerdFont-Italic.ttf) printf '998207ee63e0d2cd1490616f08a1bbfe217bd4ecf94060119048ab1e932d45bf' ;;
    *MesloLGSNerdFont-BoldItalic.ttf) printf 'cb2a9fcbc8cbd587378035a46c0dac2c9490946b67b4ab91b3230559b5cc74e9' ;;
    *) printf 'invalid' ;;
  esac
}

# Fontconfig usa candidatos exactos y prefiere el nombre largo.
test "$(FONTCONFIG_NERD_FONT_FAMILY='MesloLGS Nerd Font' FONTCONFIG_NF_FAMILY='MesloLGS NF' meslo_nerd_font_family)" = 'MesloLGS Nerd Font' || fail 'no respetó la preferencia de familia'
test "$(FONTCONFIG_NERD_FONT_FAMILY='Noto Sans' FONTCONFIG_NF_FAMILY='MesloLGS NF' meslo_nerd_font_family)" = 'MesloLGS NF' || fail 'no seleccionó MesloLGS NF tras fallback Noto Sans'
FONTCONFIG_NERD_FONT_FAMILY='MesloLGS Nerd Fonts' FONTCONFIG_NF_FAMILY='MesloLGS NF Mono' \
  meslo_nerd_font_available && fail 'una familia parecida contó como Meslo exacta'
FONTCONFIG_NERD_FONT_FAMILY='Noto Sans' FONTCONFIG_NF_FAMILY='MesloLGS NF' install_nerd_font > "$TEST_ROOT/external.out"
[[ "$MESLO_FONT_FAMILY" == 'MesloLGS NF' && "$MESLO_FONT_ORIGIN" == system ]] || fail 'no conservó la familia externa resuelta'
[[ ! -e "$HOME/curl.log" ]] || fail 'una fuente externa provocó descargas'
[[ "$(wc -l < "$ACTIVE_CYCLE_DIR/fonts.tsv" | tr -d ' ')" == 1 ]] || fail 'una fuente externa recibió ownership'
[[ ! -e "$HOME/.local/share/fonts" ]] || fail 'una fuente externa creó una copia gestionada'
FONTCONFIG_DISABLED=1 meslo_nerd_font_available && fail 'fontconfig deshabilitado contó como fuente disponible'

FONT_CORRUPT_STYLE=Italic FONTCONFIG_DISABLED=1 install_nerd_font > "$TEST_ROOT/corrupt.out"
for style in Regular Bold Italic BoldItalic; do
  [[ ! -e "$HOME/.local/share/fonts/MesloLGSNerdFont-$style.ttf" ]] || fail 'una descarga corrupta permitió una instalación parcial'
done
: > "$HOME/curl.log"

FONTCONFIG_DISABLED=1 install_nerd_font > "$TEST_ROOT/install.out"
for style in Regular Bold Italic BoldItalic; do [[ -s "$HOME/.local/share/fonts/MesloLGSNerdFont-$style.ttf" ]] || fail "falta $style"; done
[[ "$(wc -l < "$ACTIVE_CYCLE_DIR/fonts.tsv" | tr -d ' ')" == 5 ]] || fail 'tracking de fuentes incompleto'
[[ "$(wc -l < "$HOME/curl.log" | tr -d ' ')" == 4 ]] || fail 'no se descargaron exactamente cuatro TTF'
grep -Fq '/v3.5.1/patched-fonts/Meslo/S/MesloLGSNerdFont-Regular.ttf' "$HOME/curl.log" || fail 'la descarga no usa el tag oficial versionado'
if grep -Fq 'Meslo.zip' "$HOME/curl.log"; then fail 'todavía se descarga el archivo completo de Meslo'; fi

before="$(cksum "$ACTIVE_CYCLE_DIR/fonts.tsv")"
FONTCONFIG_DISABLED=1 install_nerd_font > "$TEST_ROOT/reinstall.out"
[[ "$(cksum "$ACTIVE_CYCLE_DIR/fonts.tsv")" == "$before" ]] || fail 'segunda instalación duplicó tracking'
[[ "$(wc -l < "$HOME/curl.log" | tr -d ' ')" == 4 ]] || fail 'segunda instalación repitió descargas'

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
FONTCONFIG_DISABLED=1 install_nerd_font > "$TEST_ROOT/macos-install.out"
[[ -e "$HOME/brew-font-installed" ]] || fail 'macOS no instaló el cask esperado'
grep -Fq $'homebrew-cask:font-meslo-lg-nerd-font\tmissing\tinstalled_by_cycle' "$ACTIVE_CYCLE_DIR/fonts.tsv" || fail 'macOS no registró el cask'
remove_cycle_fonts
[[ ! -e "$HOME/brew-font-installed" ]] || fail 'macOS no retiró el cask atribuible'

printf 'OK: instalación y rollback seguro de MesloLGS Nerd Font\n'
