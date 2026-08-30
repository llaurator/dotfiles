#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT="$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"

PROFILE=""
ASSUME_YES=0
MIGRATE_BASH_HISTORY=0
DRY_RUN=0

usage() {
    cat <<'HELP'
Uso:
  ./install.sh
  ./install.sh --profile personal
  ./install.sh --profile work --yes
  ./install.sh --profile server --yes
  ./install.sh --migrate-bash-history
  ./install.sh --migrate-bash-history --dry-run

Opciones:
  -p, --profile PROFILE   personal | work | server
  -y, --yes               No pedir confirmación
      --migrate-bash-history
                          Importar de forma segura ~/.bash_history en ~/.zsh_history
      --dry-run           Mostrar estadísticas de la migración sin modificar archivos
  -h, --help              Mostrar ayuda
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile) [[ $# -ge 2 ]] || die "Falta el valor de --profile"; PROFILE="$2"; shift 2 ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --migrate-bash-history) MIGRATE_BASH_HISTORY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Opción desconocida: $1" ;;
    esac
done

if [[ "$DRY_RUN" -eq 1 && "$MIGRATE_BASH_HISTORY" -ne 1 ]]; then
    die '--dry-run solo puede usarse con --migrate-bash-history.'
fi
if [[ "$MIGRATE_BASH_HISTORY" -eq 1 ]]; then
    [[ -z "$PROFILE" ]] || die '--migrate-bash-history no puede combinarse con --profile.'
    source "$ROOT_DIR/scripts/history.sh"
    migrate_bash_history "$DRY_RUN"
    exit 0
fi

detect_platform
print_banner

if [[ "$ASSUME_YES" -eq 1 && -z "$PROFILE" ]]; then
    die 'El modo --yes requiere --profile personal|work|server.'
fi
[[ -n "$PROFILE" ]] || PROFILE="$(choose_profile)"
validate_profile "$PROFILE"

printf '\n'
info "Sistema detectado"
printf '  OS:       %s\n' "$DOTFILES_OS"
printf '  Distro:   %s\n' "$DOTFILES_DISTRO"
printf '  Arch:     %s\n' "$DOTFILES_ARCH"
printf '  Host:     %s\n' "$DOTFILES_HOST"
printf '  Perfil:   %s\n\n' "$PROFILE"
print_plan "$PROFILE"

if [[ "$ASSUME_YES" -ne 1 ]]; then
    printf '\n'
    read -r -p "¿Continuar? [Y/n] " answer
    case "${answer:-Y}" in
        y|Y|yes|YES|s|S|si|SI|sí|SÍ) ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
fi

info "Instalando paquetes del sistema..."
case "$DOTFILES_OS" in
    macos) source "$ROOT_DIR/scripts/macos.sh" ;;
    linux)
        case "$DOTFILES_DISTRO" in
            arch) source "$ROOT_DIR/scripts/arch.sh" ;;
            fedora) source "$ROOT_DIR/scripts/fedora.sh" ;;
            debian) source "$ROOT_DIR/scripts/debian.sh" ;;
            *) die "Distribución Linux no soportada: $DOTFILES_DISTRO" ;;
        esac
        ;;
esac
install_system_packages

source "$ROOT_DIR/scripts/common.sh"
install_common_components
write_profile "$PROFILE"
deploy_stow_packages "$PROFILE"
configure_git_identity
configure_vscode "$PROFILE"
ensure_zsh_shell

success "Instalación terminada."
printf '\nPerfil activo: %s\nRepo:          %s\n\n' "$PROFILE" "$ROOT_DIR"
printf 'Abre una nueva terminal o ejecuta:\n  exec zsh\n'
