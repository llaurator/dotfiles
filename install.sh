#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT="$ROOT_DIR"
source "$ROOT_DIR/scripts/lib.sh"
source "$ROOT_DIR/scripts/common.sh"
source "$ROOT_DIR/scripts/state.sh"

PROFILE=""
ASSUME_YES=0
MIGRATE_BASH_HISTORY=0
DRY_RUN=0
UNINSTALL=0
SHOW_STATUS=0
BACKUP_CONFLICTS=0

usage() {
    cat <<'HELP'
Uso:
  ./install.sh
  ./install.sh --profile personal
  ./install.sh --profile work --yes
  ./install.sh --profile server --yes
  ./install.sh --profile server --yes --backup-conflicts
  ./install.sh --uninstall
  ./install.sh --uninstall --dry-run
  ./install.sh --status
  ./install.sh --migrate-bash-history
  ./install.sh --migrate-bash-history --dry-run

Opciones:
  -p, --profile PROFILE   personal | work | server
  -y, --yes               No pedir confirmación
      --migrate-bash-history
                          Importar de forma segura ~/.bash_history en ~/.zsh_history
      --uninstall         Retirar dotfiles y restaurar la baseline disponible
      --status            Mostrar el estado sin modificar archivos
      --backup-conflicts  Respaldar conflictos explícitamente antes de instalar
      --dry-run           Simular migración o desinstalación sin modificar archivos
  -h, --help              Mostrar ayuda
HELP
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile) [[ $# -ge 2 ]] || die "Falta el valor de --profile"; PROFILE="$2"; shift 2 ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --migrate-bash-history) MIGRATE_BASH_HISTORY=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --status) SHOW_STATUS=1; shift ;;
        --backup-conflicts) BACKUP_CONFLICTS=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Opción desconocida: $1" ;;
    esac
done

explicit_actions=$((MIGRATE_BASH_HISTORY + UNINSTALL + SHOW_STATUS))
(( explicit_actions <= 1 )) || die 'Elige una única acción: instalar, migrar, desinstalar o estado.'
if (( explicit_actions > 0 )) && [[ -n "$PROFILE" ]]; then
    die 'Las acciones --migrate-bash-history, --uninstall y --status no aceptan --profile.'
fi
if [[ "$DRY_RUN" -eq 1 && "$MIGRATE_BASH_HISTORY" -ne 1 && "$UNINSTALL" -ne 1 ]]; then
    die '--dry-run solo puede usarse con --migrate-bash-history o --uninstall.'
fi
if [[ "$BACKUP_CONFLICTS" -eq 1 ]] && (( explicit_actions > 0 )); then
    die '--backup-conflicts solo puede usarse al instalar.'
fi

print_banner
ACTION='install'
if (( explicit_actions == 0 )) && [[ -z "$PROFILE" && "$ASSUME_YES" -eq 0 && "$BACKUP_CONFLICTS" -eq 0 ]]; then
    ACTION="$(choose_action)"
elif [[ "$MIGRATE_BASH_HISTORY" -eq 1 ]]; then
    ACTION='migrate'
elif [[ "$UNINSTALL" -eq 1 ]]; then
    ACTION='uninstall'
elif [[ "$SHOW_STATUS" -eq 1 ]]; then
    ACTION='status'
fi

case "$ACTION" in
  exit) info 'Hasta la próxima.'; exit 0 ;;
  status) show_dotfiles_status; exit 0 ;;
  uninstall) uninstall_dotfiles "$DRY_RUN"; exit 0 ;;
  migrate)
    source "$ROOT_DIR/scripts/history.sh"
    migrate_bash_history "$DRY_RUN"
    exit 0
    ;;
esac

detect_platform

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

plan_reversible_install "$PROFILE"

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

install_common_components
begin_reversible_install "$PROFILE"
write_profile "$PROFILE"
mark_path_if_changed '.config/dotfiles/profile' profile '-'
deploy_stow_packages "$PROFILE"
configure_git_identity
mark_path_if_changed '.config/git/local.gitconfig' git '-'
configure_vscode "$PROFILE"
mark_vscode_paths_if_changed "$PROFILE"
ensure_zsh_shell

success "Instalación terminada."
printf '\nPerfil activo: %s\nRepo:          %s\n\n' "$PROFILE" "$ROOT_DIR"
printf 'Abre una nueva terminal o ejecuta:\n  exec zsh\n'
