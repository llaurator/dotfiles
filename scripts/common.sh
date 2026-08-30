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
profile_uses_nerd_font() { [[ "$1" == personal || "$1" == work ]]; }
install_nerd_font() {
  local font_dir tmp_dir name target before fingerprint expected url downloaded
  local base_url='https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.5.1/patched-fonts/Meslo/S'
  local -a missing_fonts=()
  [[ "${DOTFILES_SKIP_FONT:-0}" != 1 ]] || { info 'Fuente omitida por el entorno de pruebas.'; return 0; }
  if [[ "$DOTFILES_OS" == macos ]]; then
    if brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1; then
      [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] && ! grep -q '^homebrew-cask:' "$ACTIVE_CYCLE_DIR/fonts.tsv" && printf 'homebrew-cask:font-meslo-lg-nerd-font\talready_present\t-\n' >> "$ACTIVE_CYCLE_DIR/fonts.tsv"
      success 'MesloLGS Nerd Font ya instalada.'; return
    fi
    brew install --cask font-meslo-lg-nerd-font
    [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] && printf 'homebrew-cask:font-meslo-lg-nerd-font\tmissing\tinstalled_by_cycle\n' >> "$ACTIVE_CYCLE_DIR/fonts.tsv"
  else
    command_exists curl || { warn 'No se encontró curl; no se pudo instalar MesloLGS Nerd Font.'; return; }
    font_dir="$HOME/.local/share/fonts"; mkdir -p "$font_dir"
    tmp_dir="$(mktemp -d "$font_dir/.meslo-dotfiles.XXXXXX")" || return 1
    for name in Regular Bold Italic BoldItalic; do
      target="$font_dir/MesloLGSNerdFont-$name.ttf"; before=missing; [[ -e "$target" ]] && before="$(path_fingerprint "$target")"
      if [[ "$before" == missing ]]; then
        missing_fonts+=("$name")
      elif [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] && ! grep -Fq ".local/share/fonts/${target##*/}" "$ACTIVE_CYCLE_DIR/fonts.tsv"; then
        printf '%s\t%s\t%s\n' ".local/share/fonts/${target##*/}" "$before" "$before" >> "$ACTIVE_CYCLE_DIR/fonts.tsv"
      fi
    done
    for name in "${missing_fonts[@]}"; do
      case "$name" in
        Regular) expected='f3148b1e05c1dcf86785020d1d144524b9458deaab17505b88ecfe1694543214' ;;
        Bold) expected='63ff060fbe6db68ee719137640217f28da72fb1b78c1c41f254451f3fca1f236' ;;
        Italic) expected='998207ee63e0d2cd1490616f08a1bbfe217bd4ecf94060119048ab1e932d45bf' ;;
        BoldItalic) expected='cb2a9fcbc8cbd587378035a46c0dac2c9490946b67b4ab91b3230559b5cc74e9' ;;
      esac
      downloaded="$tmp_dir/MesloLGSNerdFont-$name.ttf"
      url="$base_url/MesloLGSNerdFont-$name.ttf"
      if ! curl -fL --proto '=https' --tlsv1.2 -o "$downloaded" "$url" ||
         [[ ! -s "$downloaded" ]] || [[ "$(sha256_stream < "$downloaded")" != "$expected" ]]; then
        rm -rf -- "$tmp_dir"
        warn 'No se pudo descargar o verificar MesloLGS Nerd Font.'
        return 0
      fi
      chmod 644 "$downloaded"
    done
    for name in "${missing_fonts[@]}"; do
      target="$font_dir/MesloLGSNerdFont-$name.ttf"
      [[ ! -e "$target" && ! -L "$target" ]] || { rm -rf -- "$tmp_dir"; warn "La fuente apareció durante la instalación y se conserva: $target"; return 0; }
    done
    for name in "${missing_fonts[@]}"; do
      target="$font_dir/MesloLGSNerdFont-$name.ttf"
      mv "$tmp_dir/MesloLGSNerdFont-$name.ttf" "$target"
      fingerprint="$(path_fingerprint "$target")"
      [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] && printf '%s\tmissing\t%s\n' ".local/share/fonts/${target##*/}" "$fingerprint" >> "$ACTIVE_CYCLE_DIR/fonts.tsv"
    done
    rm -rf -- "$tmp_dir"
    if command_exists fc-cache; then fc-cache -f "$font_dir" >/dev/null 2>&1 || warn 'fontconfig no pudo actualizar la caché de usuario.'; else warn 'fontconfig no está disponible; actualiza la caché de fuentes manualmente.'; fi
  fi
  success 'MesloLGS Nerd Font instalada.'
  info 'Si los iconos no se muestran correctamente, selecciona "MesloLGS NF" como fuente en tu emulador de terminal.'
}
write_profile(){ mkdir -p "$HOME/.config/dotfiles"; printf '%s\n' "$1" > "$HOME/.config/dotfiles/profile"; success 'Perfil guardado en ~/.config/dotfiles/profile'; }
stow_packages_for_profile() {
  local profile="$1"
  STOW_PACKAGES=(zsh git btop)
  case "$profile" in personal|work) STOW_PACKAGES+=(ssh vscode) ;; esac
}
deploy_stow_packages(){
  local profile="$1" package
  stow_packages_for_profile "$profile"
  info 'Desplegando dotfiles con GNU Stow...'
  for package in "${STOW_PACKAGES[@]}"; do
    [[ -d "$DOTFILES_ROOT/$package" ]] || die "Paquete Stow inexistente: $package"
    stow --restow --no-folding --dir="$DOTFILES_ROOT" --target="$HOME" "$package"
    mark_stow_package_owned "$package"
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
  git_name="$(git config --get user.name 2>/dev/null || true)"
  git_email="$(git config --get user.email 2>/dev/null || true)"
  if [[ -n "$git_name" && -n "$git_email" ]]; then
    success 'Identidad Git ya configurada.'
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
    if cmp -s "$temporary" "$settings_target"; then
      rm -f "$temporary"
      success 'VS Code: settings.json ya está actualizado.'
      return 0
    fi
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
    ms-python.vscode-python-envs) printf 'Python Environments' ;;
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
ensure_zsh_shell(){
  local zsh_path current
  if [[ "$DOTFILES_OS" == macos && -x /bin/zsh ]]; then zsh_path=/bin/zsh; else zsh_path="$(command -v zsh || true)"; fi
  [[ -n "$zsh_path" ]] || { warn 'No se ha encontrado zsh.'; return; }
  current="$(current_login_shell)"
  if [[ "$current" == "$zsh_path" ]]; then success 'Zsh ya es el shell por defecto.'; return; fi
  info 'Configurando Zsh como shell por defecto...'
  if chsh -s "$zsh_path"; then
    record_shell_changed "$zsh_path"
    success "Shell por defecto cambiado a $zsh_path"
    info 'El cambio será efectivo al iniciar una nueva sesión de usuario.'
    printf '  Para usar Zsh ahora en esta terminal: exec zsh\n'
  else warn "Ejecuta manualmente: chsh -s $zsh_path"; fi
}
