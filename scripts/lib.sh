#!/usr/bin/env bash
DOTFILES_OS=''
DOTFILES_DISTRO=''
DOTFILES_ARCH=''
DOTFILES_HOST=''
SUDO_VALIDATED=0

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'; MAGENTA=$'\033[0;35m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
info(){ printf '%sℹ%s  %s\n' "$CYAN" "$RESET" "$*"; }
success(){ printf '%s✓%s  %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s!%s  %s\n' "$YELLOW" "$RESET" "$*"; }
die(){ printf '%s✗%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
command_exists(){ command -v "$1" >/dev/null 2>&1; }
login_shell_is_registered(){
  local shell_path="$1" shells_file="${2:-/etc/shells}" entry
  [[ "$shell_path" == /* && "$shell_path" != *$'\n'* && "$shell_path" != *$'\t'* ]] || return 1
  [[ -f "$shells_file" && -r "$shells_file" ]] || return 1
  # Use shell builtins here: validating a PATH-derived executable must not
  # itself trust another executable resolved through that same PATH.
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ "$entry" == "$shell_path" ]] && return 0
  done < "$shells_file"
  return 1
}
is_valid_login_shell(){
  local shell_path="$1"
  [[ "$shell_path" == /* && "$shell_path" != *$'\n'* && "$shell_path" != *$'\t'* ]] || return 1
  if [[ "${DOTFILES_OS:-}" == macos ]]; then
    # Prefer the system registry on macOS too, so an existing /bin/bash can be
    # restored. Keep Apple's supported /bin/zsh as a fallback if the registry
    # cannot be read.
    if [[ -f /etc/shells && -r /etc/shells ]]; then
      login_shell_is_registered "$shell_path" /etc/shells
    else
      [[ "$shell_path" == /bin/zsh && -x /bin/zsh ]]
    fi
  else
    login_shell_is_registered "$shell_path" /etc/shells
  fi
}
is_root_user(){ local uid; uid="$(id -u)" || return 1; [[ "$uid" == 0 ]]; }
validate_sudo_once(){
  [[ "$SUDO_VALIDATED" -eq 0 ]] || return 0
  is_root_user && { SUDO_VALIDATED=1; return 0; }
  command_exists sudo || { warn 'Se necesitan privilegios y sudo no está disponible.'; return 1; }
  info 'Validando privilegios para la fase que modifica el sistema...'
  sudo -v || { warn 'No se pudieron validar los privilegios con sudo.'; return 1; }
  SUDO_VALIDATED=1
}
run_privileged(){
  if is_root_user; then "$@"; return; fi
  validate_sudo_once || return 1
  sudo "$@"
}
privileged_chsh(){
  local shell_path="$1" target_user
  is_valid_login_shell "$shell_path" || { warn "Se rechazó un shell de login no válido: $shell_path"; return 1; }
  target_user="$(id -un)" || return 1
  run_privileged chsh -s "$shell_path" "$target_user"
}
print_banner(){ printf '%s%s' "$MAGENTA" "$BOLD"; cat <<'BANNER'
╭─────────────────────────────────────────╮
│          🦇 DOTFILES INSTALLER          │
╰─────────────────────────────────────────╯
BANNER
printf '%s' "$RESET"; }
detect_platform(){
  DOTFILES_ARCH="$(uname -m)"; DOTFILES_HOST="$(hostname -s 2>/dev/null || hostname)"
  case "$(uname -s)" in
    Darwin) DOTFILES_OS="macos"; DOTFILES_DISTRO="macos" ;;
    Linux)
      DOTFILES_OS="linux"
      if command_exists pacman; then DOTFILES_DISTRO="arch"
      elif command_exists dnf; then DOTFILES_DISTRO="fedora"
      elif command_exists apt-get; then DOTFILES_DISTRO="debian"
      else DOTFILES_DISTRO="unknown"; fi ;;
    *) die "Sistema operativo no soportado: $(uname -s)" ;;
  esac
  export DOTFILES_OS DOTFILES_DISTRO DOTFILES_ARCH DOTFILES_HOST
}
choose_profile(){
  local choice
  printf '%s\n' 'Selecciona el perfil:' >&2
  printf '  1) Personal\n  2) Trabajo\n  3) Servidor / CT / VM\n\n' >&2
  read -r -p '> ' choice
  case "$choice" in 1|personal) echo personal ;; 2|work|trabajo) echo work ;; 3|server|servidor) echo server ;; *) die 'Perfil no válido' ;; esac
}
choose_action(){
  local choice
  printf '%s\n' '¿Qué quieres hacer?' >&2
  printf '  1) Instalar / actualizar dotfiles\n  2) Restaurar / desinstalar dotfiles\n  3) Migrar historial Bash → Zsh\n  4) Estado\n  5) Salir\n\n' >&2
  read -r -p '> ' choice
  case "$choice" in
    1|install|instalar) echo install ;;
    2|uninstall|restore|restaurar) echo uninstall ;;
    3|migrate|migrar) echo migrate ;;
    4|status|estado) echo status ;;
    5|exit|salir) echo exit ;;
    *) die 'Acción no válida' ;;
  esac
}
validate_profile(){ case "$1" in personal|work|server) ;; *) die "Perfil no válido: $1" ;; esac; }
print_plan(){
  printf '%sSe instalará:%s\n' "$BOLD" "$RESET"
  printf '  ✓ zsh\n  ✓ git\n  ✓ stow\n  ✓ fzf\n  ✓ zoxide\n  ✓ eza\n  ✓ bat\n  ✓ ripgrep\n  ✓ btop\n  ✓ grc\n  ✓ Oh My Zsh\n  ✓ Powerlevel10k\n  ✓ plugins Zsh\n'
  case "$1" in personal) printf '  ✓ configuración SSH cliente\n' ;; work) printf '  ✓ configuración SSH cliente\n  ✓ perfil de trabajo\n' ;; server) printf '  ✓ perfil ligero de servidor\n' ;; esac
  case "$1" in personal|work) printf '  ✓ VS Code (si está disponible) y extensiones mínimas\n' ;; esac
}
