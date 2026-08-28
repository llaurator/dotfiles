#!/usr/bin/env bash
install_git_repo(){ local repo="$1" dest="$2"; if [[ -d "$dest/.git" ]]; then info "Ya existe: $dest"; return; fi; if [[ -e "$dest" ]]; then warn "Existe $dest pero no parece un repositorio Git; no se modifica."; return; fi; git clone --depth=1 "$repo" "$dest"; }
install_common_components(){
  info 'Instalando componentes Zsh desde upstream...'
  install_git_repo https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  install_git_repo https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  install_git_repo https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  install_git_repo https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  install_git_repo https://github.com/zsh-users/zsh-history-substring-search.git "$HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search"
}
write_profile(){ mkdir -p "$HOME/.config/dotfiles"; printf '%s\n' "$1" > "$HOME/.config/dotfiles/profile"; success 'Perfil guardado en ~/.config/dotfiles/profile'; }
stow_preflight() {
  local package source relative target
  local conflicts=()
  for package in "$@"; do
    while IFS= read -r -d '' source; do
      relative="${source#"$DOTFILES_ROOT/$package/"}"
      target="$HOME/$relative"
      if [[ -e "$target" && ! -L "$target" && ! -d "$target" ]]; then
        conflicts+=("$target")
      fi
    done < <(find "$DOTFILES_ROOT/$package" -type f -print0)
  done
  if (( ${#conflicts[@]} )); then
    warn 'Stow ha detectado archivos existentes que no se sobrescribirán:'
    printf '  - %s\n' "${conflicts[@]}" >&2
    die 'Migra o respalda esos archivos manualmente y vuelve a ejecutar el instalador. No uses stow --adopt a ciegas.'
  fi
}
deploy_stow_packages(){
  local profile="$1" package
  local packages=(zsh git btop)
  case "$profile" in personal|work) packages+=(ssh vscode) ;; esac
  info 'Desplegando dotfiles con GNU Stow...'
  stow_preflight "${packages[@]}"
  for package in "${packages[@]}"; do
    [[ -d "$DOTFILES_ROOT/$package" ]] || die "Paquete Stow inexistente: $package"
    stow --restow --no-folding --dir="$DOTFILES_ROOT" --target="$HOME" "$package"
    success "Stow: $package"
  done
  if [[ "$profile" != server ]]; then
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/config.d"
    if ! compgen -G "$HOME/.ssh/config.d/*.conf" >/dev/null; then
      info 'SSH configurado.'
      printf '  No hay hosts locales en ~/.ssh/config.d/*.conf\n'
      printf '  Puedes copiar/adaptar los ejemplos incluidos en el repositorio.\n'
    fi
  fi
}
configure_git_identity() {
  local git_name git_email answer name email local_config
  git_name="$(git config --global --get user.name 2>/dev/null || true)"
  git_email="$(git config --global --get user.email 2>/dev/null || true)"
  if [[ -n "$git_name" && -n "$git_email" ]]; then
    success 'Se conserva la identidad Git existente.'
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    warn 'No hay una identidad Git completa; el modo --yes no la configura.'
    return 0
  fi
  if ! read -r -p 'No hay una identidad Git configurada. ¿Quieres configurarla ahora? [s/N] ' answer; then
    warn 'No se pudo leer la respuesta; la identidad Git queda sin configurar.'
    return 0
  fi
  case "$answer" in
    s|S|si|SI|sí|SÍ)
      name=""
      email=""
      while [[ -z "$name" ]]; do
        if ! read -r -p 'Nombre para commits Git: ' name; then
          warn 'Entrada finalizada; la identidad Git queda sin configurar.'
          return 0
        fi
        [[ -n "$name" ]] || warn 'El nombre no puede estar vacío.'
      done
      while [[ -z "$email" ]]; do
        if ! read -r -p 'Email para commits Git: ' email; then
          warn 'Entrada finalizada; la identidad Git queda sin configurar.'
          return 0
        fi
        [[ -n "$email" ]] || warn 'El email no puede estar vacío.'
      done
      local_config="$HOME/.config/git/local.gitconfig"
      mkdir -p "${local_config%/*}"
      [[ -n "$git_name" ]] || git config --file "$local_config" user.name "$name"
      [[ -n "$git_email" ]] || git config --file "$local_config" user.email "$email"
      chmod 600 "$local_config"
      success 'Identidad Git guardada en ~/.config/git/local.gitconfig.'
      ;;
    *) info 'La identidad Git queda sin configurar.' ;;
  esac
}
vscode_file_mode() {
  case "$DOTFILES_OS" in
    macos) stat -f '%Lp' "$1" ;;
    linux) stat -c '%a' "$1" ;;
  esac
}
merge_vscode_settings() {
  local settings_source="$1" settings_target="$2"
  local settings_dir backup temporary mode
  settings_dir="${settings_target%/*}"
  backup="$settings_target.pre-dotfiles"
  mkdir -p "$settings_dir"

  if ! jq -e 'type == "object"' "$settings_source" >/dev/null 2>&1; then
    warn "Los settings gestionados no son un objeto JSON válido: $settings_source"
    return 1
  fi
  if [[ -e "$settings_target" || -L "$settings_target" ]]; then
    if ! jq -e 'type == "object"' "$settings_target" >/dev/null 2>&1; then
      warn "VS Code: JSON local inválido; no se modifica: $settings_target"
      return 1
    fi
  fi

  temporary="$(mktemp "$settings_dir/.settings.json.dotfiles.XXXXXX")" || {
    warn "VS Code: no se pudo crear el fichero temporal en $settings_dir"
    return 1
  }
  if [[ -e "$settings_target" || -L "$settings_target" ]]; then
    if ! jq -S -s '.[0] * .[1]' "$settings_target" "$settings_source" > "$temporary" ||
       ! jq -e 'type == "object"' "$temporary" >/dev/null 2>&1; then
      rm -f "$temporary"
      warn 'VS Code: no se pudo generar un merge JSON válido; los settings locales no se modifican.'
      return 1
    fi
    mode="$(vscode_file_mode "$settings_target")" || {
      rm -f "$temporary"
      warn "VS Code: no se pudieron consultar los permisos de $settings_target"
      return 1
    }
    chmod "$mode" "$temporary" || {
      rm -f "$temporary"
      warn 'VS Code: no se pudieron preservar los permisos del settings.json local.'
      return 1
    }
    if [[ ! -e "$backup" && ! -L "$backup" ]] && ! cp -p "$settings_target" "$backup"; then
      rm -f "$temporary"
      warn "VS Code: no se pudo crear el backup $backup; no se modifica el original."
      return 1
    fi
  else
    if ! jq -S '.' "$settings_source" > "$temporary" ||
       ! jq -e 'type == "object"' "$temporary" >/dev/null 2>&1; then
      rm -f "$temporary"
      warn 'VS Code: no se pudo preparar un settings.json válido.'
      return 1
    fi
    chmod 644 "$temporary" || {
      rm -f "$temporary"
      warn 'VS Code: no se pudieron establecer los permisos del nuevo settings.json.'
      return 1
    }
  fi
  if ! mv -f "$temporary" "$settings_target"; then
    rm -f "$temporary"
    warn "VS Code: no se pudo aplicar el settings.json fusionado: $settings_target"
    return 1
  fi
  success 'VS Code: settings.json gestionado y validado.'
}
vscode_extension_name() {
  case "$1" in
    esbenp.prettier-vscode) printf 'Prettier' ;;
    charliermarsh.ruff) printf 'Ruff' ;;
    MS-CEINTL.vscode-language-pack-es) printf 'Spanish Language Pack' ;;
    dracula-theme.theme-dracula) printf 'Dracula Official' ;;
    *) printf '%s' "$1" ;;
  esac
}
configure_vscode() {
  local profile="$1" settings_source settings_dir settings_target extension installed_extensions extension_name
  [[ "$profile" != server ]] || return 0
  settings_source="$HOME/.config/dotfiles/vscode/settings.json"
  case "$DOTFILES_OS" in
    macos) settings_dir="$HOME/Library/Application Support/Code/User" ;;
    linux) settings_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
  esac
  settings_target="$settings_dir/settings.json"
  if ! merge_vscode_settings "$settings_source" "$settings_target"; then
    warn 'VS Code: los settings gestionados no pudieron aplicarse; la instalación continúa.'
  fi
  if ! command_exists code; then
    warn 'No se encontró code; se omite la instalación de extensiones.'
    return 0
  fi
  installed_extensions="$(code --list-extensions 2>/dev/null || true)"
  while IFS= read -r extension; do
    [[ -n "$extension" && "$extension" != \#* ]] || continue
    extension_name="$(vscode_extension_name "$extension")"
    if command grep -Fxiq -- "$extension" <<< "$installed_extensions"; then
      success "VS Code: $extension_name ya instalado."
    else
      code --install-extension "$extension"
    fi
  done < "$HOME/.config/dotfiles/vscode/extensions.txt"
}
ensure_zsh_shell(){ local zsh_path; if [[ "$DOTFILES_OS" == macos && -x /bin/zsh ]]; then zsh_path=/bin/zsh; else zsh_path="$(command -v zsh || true)"; fi; [[ -n "$zsh_path" ]] || { warn 'No se ha encontrado zsh.'; return; }; if [[ "${SHELL:-}" == "$zsh_path" ]]; then success 'Zsh ya es el shell por defecto.'; return; fi; info 'Configurando Zsh como shell por defecto...'; if chsh -s "$zsh_path"; then success "Shell por defecto cambiado a $zsh_path"; else warn "Ejecuta manualmente: chsh -s $zsh_path"; fi; }
