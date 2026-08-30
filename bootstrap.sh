#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL='https://github.com/llaurator/dotfiles.git'
readonly DEFAULT_REF='main'

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

info() { printf '%sℹ%s  %s\n' "$CYAN" "$RESET" "$*"; }
success() { printf '%s✓%s  %s\n' "$GREEN" "$RESET" "$*"; }
die() { printf '%s✗%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

git_is_usable() {
    local git_path
    git_path="$(command -v git 2>/dev/null)" || return 1

    # /usr/bin/git puede abrir el instalador de Command Line Tools en macOS.
    if [[ "$(uname -s)" == 'Darwin' && "$git_path" == '/usr/bin/git' ]]; then
        command_exists xcode-select && xcode-select -p >/dev/null 2>&1 || return 1
    fi

    "$git_path" --version >/dev/null 2>&1
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        die 'Se necesita sudo para instalar Git.'
    fi
}

install_git() {
    local brew_bin=''

    info 'Git no está disponible; instalando únicamente Git...'
    case "$(uname -s)" in
        Darwin)
            if command_exists brew; then
                brew_bin="$(command -v brew)"
            elif [[ -x /opt/homebrew/bin/brew ]]; then
                brew_bin='/opt/homebrew/bin/brew'
            elif [[ -x /usr/local/bin/brew ]]; then
                brew_bin='/usr/local/bin/brew'
            else
                die 'Git no está disponible. Instala Homebrew o las Command Line Tools y vuelve a intentarlo.'
            fi
            "$brew_bin" install git
            PATH="${brew_bin%/*}:$PATH"
            export PATH
            ;;
        Linux)
            if command_exists pacman; then
                run_as_root pacman -S --needed git
            elif command_exists dnf; then
                run_as_root dnf install -y git
            elif command_exists apt-get; then
                run_as_root apt-get update
                run_as_root apt-get install -y git
            else
                die 'No se encontró pacman, dnf ni apt-get para instalar Git.'
            fi
            ;;
        *)
            die "Sistema no soportado para instalar Git: $(uname -s)"
            ;;
    esac

    hash -r
    git_is_usable || die 'Git sigue sin estar disponible después de la instalación.'
    success 'Git disponible.'
}

origin_is_expected() {
    case "$1" in
        https://github.com/llaurator/dotfiles|\
        https://github.com/llaurator/dotfiles.git|\
        git@github.com:llaurator/dotfiles.git|\
        ssh://git@github.com/llaurator/dotfiles.git) return 0 ;;
        *) return 1 ;;
    esac
}

validate_existing_repository() {
    local origin_url

    [[ ! -L "$DOTFILES_DIR" ]] || die "La ruta es un enlace simbólico inesperado: $DOTFILES_DIR"
    [[ -d "$DOTFILES_DIR/.git" ]] ||
        die "La ruta existe, pero no es el repositorio Git esperado: $DOTFILES_DIR"
    git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "La ruta existe, pero no es un repositorio Git: $DOTFILES_DIR"
    origin_url="$(git -C "$DOTFILES_DIR" config --get remote.origin.url || true)"
    origin_is_expected "$origin_url" ||
        die "El repositorio de $DOTFILES_DIR no corresponde a $REPOSITORY_URL"
}

require_clean_worktree() {
    if [[ -n "$(git -C "$DOTFILES_DIR" status --porcelain --untracked-files=normal)" ]]; then
        die "Hay cambios locales en $DOTFILES_DIR; se conservan intactos y la actualización se cancela."
    fi
}

fetch_repository() {
    info 'Buscando actualizaciones...'
    git -C "$DOTFILES_DIR" fetch --prune --tags origin
}

update_main() {
    local before after

    git -C "$DOTFILES_DIR" show-ref --verify --quiet refs/remotes/origin/main ||
        die 'El remoto origin no contiene la rama main.'

    if git -C "$DOTFILES_DIR" show-ref --verify --quiet refs/heads/main; then
        git -C "$DOTFILES_DIR" merge-base --is-ancestor refs/heads/main refs/remotes/origin/main ||
            die 'La rama main local contiene cambios o ha divergido; no se puede actualizar por fast-forward.'
        before="$(git -C "$DOTFILES_DIR" rev-parse refs/heads/main)"
        git -C "$DOTFILES_DIR" checkout --no-overwrite-ignore main >/dev/null
        git -C "$DOTFILES_DIR" merge --ff-only refs/remotes/origin/main >/dev/null
    else
        before=''
        git -C "$DOTFILES_DIR" checkout --no-overwrite-ignore -b main --track origin/main >/dev/null
    fi

    after="$(git -C "$DOTFILES_DIR" rev-parse HEAD)"
    if [[ "$before" == "$after" ]]; then
        success 'El repositorio ya está actualizado en main.'
    else
        success 'Repositorio actualizado por fast-forward en main.'
    fi
}

checkout_ref() {
    local requested_ref="$1" target_ref='' target_commit

    if git -C "$DOTFILES_DIR" show-ref --verify --quiet "refs/tags/$requested_ref"; then
        target_ref="refs/tags/$requested_ref"
    elif [[ "$requested_ref" == refs/tags/* ]] &&
         git -C "$DOTFILES_DIR" show-ref --verify --quiet "$requested_ref"; then
        target_ref="$requested_ref"
    elif git -C "$DOTFILES_DIR" show-ref --verify --quiet "refs/remotes/origin/$requested_ref"; then
        target_ref="refs/remotes/origin/$requested_ref"
    elif [[ "$requested_ref" == refs/heads/* ]] &&
         git -C "$DOTFILES_DIR" show-ref --verify --quiet \
             "refs/remotes/origin/${requested_ref#refs/heads/}"; then
        target_ref="refs/remotes/origin/${requested_ref#refs/heads/}"
    elif git -C "$DOTFILES_DIR" rev-parse --verify --quiet "${requested_ref}^{commit}" >/dev/null; then
        target_ref="$requested_ref"
    else
        die "No se encontró el ref solicitado en origin: $requested_ref"
    fi

    target_commit="$(git -C "$DOTFILES_DIR" rev-parse "${target_ref}^{commit}")"
    git -C "$DOTFILES_DIR" checkout --detach --no-overwrite-ignore "$target_commit" >/dev/null
    success "Ref $requested_ref seleccionado en detached HEAD."
}

prepare_repository() {
    local requested_ref="$1" parent_directory

    if [[ -e "$DOTFILES_DIR" ]]; then
        validate_existing_repository
    else
        info 'Clonando dotfiles...'
        parent_directory="${DOTFILES_DIR%/*}"
        [[ -n "$parent_directory" ]] || parent_directory='/'
        mkdir -p "$parent_directory"
        git clone -- "$REPOSITORY_URL" "$DOTFILES_DIR"
        success "Repositorio clonado en $DOTFILES_DIR"
    fi

    require_clean_worktree
    fetch_repository
    if [[ "$requested_ref" == "$DEFAULT_REF" ]]; then
        update_main
    else
        checkout_ref "$requested_ref"
    fi
}

main() {
    local requested_ref="$DEFAULT_REF"
    local -a installer_args=()

    while (( $# > 0 )); do
        case "$1" in
            --ref)
                (( $# >= 2 )) || die 'Falta el valor de --ref.'
                requested_ref="$2"
                shift 2
                ;;
            --ref=*)
                requested_ref="${1#--ref=}"
                shift
                ;;
            --)
                shift
                installer_args+=("$@")
                break
                ;;
            *)
                installer_args+=("$1")
                shift
                ;;
        esac
    done

    printf '🦇 Dotfiles bootstrap\n\n'
    git_is_usable || install_git

    [[ -n "$requested_ref" && "$requested_ref" != -* ]] || die 'Valor de --ref no válido.'
    if ! git check-ref-format --branch "$requested_ref" >/dev/null 2>&1; then
        [[ "$requested_ref" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "Ref no válido: $requested_ref"
    fi

    DOTFILES_DIR="${DOTFILES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles}"
    [[ "$DOTFILES_DIR" == /* ]] || die 'DOTFILES_DIR debe ser una ruta absoluta.'
    export DOTFILES_DIR

    prepare_repository "$requested_ref"
    success "Repositorio disponible en $DOTFILES_DIR"
    info 'Ejecutando instalador...'
    "$DOTFILES_DIR/install.sh" "${installer_args[@]}"
}

main "$@"
