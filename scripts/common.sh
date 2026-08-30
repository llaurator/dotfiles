#!/usr/bin/env bash
install_git_repo(){ local repo="$1" dest="$2"; if [[ -d "$dest/.git" ]]; then info "Ya existe: $dest"; return; fi; if [[ -e "$dest" ]]; then warn "Existe $dest pero no parece un repositorio Git; no se modifica."; return; fi; git clone --depth=1 "$repo" "$dest"; }
install_common_components(){
  install_resolved_zsh_components
}
profile_uses_nerd_font() { [[ "$1" == personal || "$1" == work ]]; }
meslo_nerd_font_candidates() { printf '%s\n' 'MesloLGS Nerd Font' 'MesloLGS NF'; }
meslo_nerd_font_family() {
  local candidate family
  command_exists fc-list && command_exists fc-match || return 1
  while IFS= read -r candidate; do
    family="$(fc-match --format '%{family}\n' "$candidate" 2>/dev/null | sed -n '1p')" || continue
    [[ "$family" == "$candidate" ]] && { printf '%s' "$family"; return 0; }
  done < <(meslo_nerd_font_candidates)
  return 1
}
meslo_nerd_font_resolution() {
  local family
  if family="$(meslo_nerd_font_family)"; then
    if [[ "${MESLO_FONT_ORIGIN:-}" == managed && "${MESLO_FONT_FAMILY:-}" == "$family" ]]; then printf 'managed\t%s\n' "$family"; else printf 'system\t%s\n' "$family"; fi
  else
    printf 'missing\tMesloLGS Nerd Font\n'
  fi
}
meslo_nerd_font_available() {
  meslo_nerd_font_family >/dev/null
}
upstream_component_status() { local name="$1" component="$2" state; IFS=$'\t' read -r state _ < <(resolve_zsh_component "$component"); case "$state" in managed) printf '  ✓ %s (gestionado)\n' "$name";; external) printf '  ✓ %s (externo)\n' "$name";; missing) printf '  + %s (pendiente)\n' "$name";; esac; }
print_install_preflight() {
  local profile="$1" package
  get_system_packages
  printf '%sPreflight (solo lectura):%s\n' "$BOLD" "$RESET"
  printf '\nPaquetes:\n'
  for package in "${SYSTEM_PACKAGES[@]}"; do
    if package_is_installed "$package"; then printf '  ✓ %s (ya instalado)\n' "$package"; else printf '  + %s\n' "$package"; fi
  done
  printf '\nSe configurará:\n  • Zsh\n  • Git\n  • dotfiles con Stow\n'
  [[ "$profile" == server ]] || printf '  • SSH cliente\n  • VS Code si está disponible\n'
  printf '\nUpstream Zsh:\n'
  upstream_component_status 'Oh My Zsh' omz
  upstream_component_status 'Powerlevel10k' p10k
  upstream_component_status 'zsh-autosuggestions' autosuggestions
  upstream_component_status 'zsh-syntax-highlighting' syntax
  upstream_component_status 'zsh-history-substring-search' history
  if profile_uses_nerd_font "$profile"; then
    printf '\nFuente:\n'
    IFS=$'\t' read -r font_state font_family < <(meslo_nerd_font_resolution)
    if [[ "$font_state" == system ]]; then printf '  ✓ %s (sistema)\n' "$font_family"; else printf '  + MesloLGS Nerd Font (se instalará)\n'; fi
  fi
  if (( ${#CONFLICT_RELS[@]} )); then
    printf '\nConflictos Stow:\n'
    for package in "${CONFLICT_RELS[@]}"; do printf '  ! ~/%s ya existe y no está gestionado por dotfiles\n' "$package"; done
    if [[ "$BACKUP_CONFLICTS" -eq 1 ]]; then
      printf '  Se respaldarán solo después de confirmar.\n'
    else
      printf '  No se sobrescribirán; la instalación requerirá cancelar o autorizar una copia de seguridad.\n'
    fi
  fi
}
# shellcheck disable=SC2034 # Consumida por los scripts de plataforma después de source.
select_vscode_install() {
  local profile="$1" answer prompt
  REQUEST_INSTALL_VSCODE=0
  [[ "$profile" != server ]] || return 0
  command_exists code && return 0
  if [[ "$DOTFILES_DISTRO" == debian ]]; then
    [[ "$INSTALL_VSCODE" -eq 0 ]] || die '--install-vscode no está disponible en Debian/Ubuntu.'
    return 0
  fi
  if [[ "$INSTALL_VSCODE" -eq 1 ]]; then
    REQUEST_INSTALL_VSCODE=1
    return 0
  fi
  [[ "$ASSUME_YES" -eq 0 ]] || return 0
  case "$DOTFILES_DISTRO" in
    arch) prompt='¿Quieres instalar Visual Studio Code desde el repositorio oficial de Arch? [s/N] ' ;;
    *) prompt='¿Quieres instalar Visual Studio Code desde el repositorio oficial de Microsoft? [s/N] ' ;;
  esac
  if ! read -r -p "$prompt" answer; then
    info 'VS Code no se instalará.'
    return 0
  fi
  case "$answer" in
    s|S|si|SI|sí|SÍ) REQUEST_INSTALL_VSCODE=1 ;;
    *) info 'VS Code no se instalará.' ;;
  esac
}
select_konsole_configure() {
  local profile="$1" answer
  REQUEST_CONFIGURE_KONSOLE=0
  [[ "$profile" != server ]] || return 0
  command_exists konsole || return 0
  if [[ "$CONFIGURE_KONSOLE" -eq 1 ]]; then
    REQUEST_CONFIGURE_KONSOLE=1
    return 0
  fi
  [[ "$ASSUME_YES" -eq 0 ]] || return 0
  if ! read -r -p '¿Quieres configurar Konsole con Dracula + MesloLGS Nerd Font? [s/N] ' answer; then
    info 'Konsole no se configurará.'
    return 0
  fi
  case "$answer" in s|S|si|SI|sí|SÍ) REQUEST_CONFIGURE_KONSOLE=1 ;; *) info 'Konsole no se configurará.' ;; esac
}
konsole_font_family() {
  local font_file="$HOME/.local/share/fonts/MesloLGSNerdFont-Regular.ttf" family
  if [[ -n "${MESLO_FONT_FAMILY:-}" ]]; then printf '%s' "$MESLO_FONT_FAMILY"; return 0; fi
  command_exists fc-query || return 1
  [[ -f "$font_file" && ! -L "$font_file" ]] || return 1
  family="$(fc-query --format '%{family}\n' "$font_file" 2>/dev/null | sed -n '1p')"
  [[ -n "$family" && "$family" != *$'\n'* && "$family" != *,* ]] || return 1
  printf '%s' "$family"
}
write_konsole_default_profile() {
  local source="$1" target="$2" temporary="$3"
  if [[ -e "$source" || -L "$source" ]]; then
    [[ -f "$source" && ! -L "$source" ]] || return 1
    awk '
      /^\[Desktop Entry\]$/ {
        if (in_desktop && !written) print "DefaultProfile=Dotfiles.profile"
        in_desktop=1; saw_desktop=1; print; next
      }
      /^\[/ {
        if (in_desktop && !written) print "DefaultProfile=Dotfiles.profile"
        in_desktop=0; print; next
      }
      {
        if (in_desktop && $0 ~ /^DefaultProfile=/) {
          if (!written) print "DefaultProfile=Dotfiles.profile"
          written=1; next
        }
        print
      }
      END {
        if (in_desktop && !written) print "DefaultProfile=Dotfiles.profile"
        if (!saw_desktop) print "\n[Desktop Entry]\nDefaultProfile=Dotfiles.profile"
      }
    ' "$source" > "$temporary"
  else
    printf '[Desktop Entry]\nDefaultProfile=Dotfiles.profile\n' > "$temporary"
  fi
  chmod 600 "$temporary"
  mv -f "$temporary" "$target"
}
configure_konsole() {
  local profile="$1" scheme_dir="$HOME/.local/share/konsole" scheme="$HOME/.local/share/konsole/Dracula.colorscheme"
  local profile_file="$scheme_dir/Dotfiles.profile" konsolerc="$HOME/.config/konsolerc" font_family downloaded install_tmp profile_tmp config_tmp
  local source_url="${DOTFILES_KONSOLE_SOURCE_URL:-https://raw.githubusercontent.com/dracula/konsole/d525667c48b37f76aa28df8968e988ba219d4448/Dracula.colorscheme}"
  local expected_sha256="${DOTFILES_KONSOLE_SHA256:-cd933a4c79b782afc2e91c41f6d4342313b50f115f41b7a2eaf1196e889c5e8b}"
  [[ "$profile" != server && "$REQUEST_CONFIGURE_KONSOLE" -eq 1 ]] || return 0
  command_exists konsole || return 0
  font_family="$(konsole_font_family)" || { warn 'Konsole: no se pudo detectar MesloLGS Nerd Font con fontconfig; no se modifica la configuración.'; return 0; }
  [[ ! -e "$profile_file" && ! -L "$profile_file" ]] || { warn 'Konsole: Dotfiles.profile ya existe y se conserva; no se modifica Konsole.'; return 0; }
  if [[ -e "$scheme" || -L "$scheme" ]]; then
    [[ -f "$scheme" && ! -L "$scheme" && "$(sha256_stream < "$scheme")" == "$expected_sha256" ]] || { warn 'Konsole: Dracula.colorscheme ya existe y se conserva; no se modifica Konsole.'; return 0; }
  fi
  downloaded="$(mktemp "${TMPDIR:-/tmp}/dotfiles-konsole.XXXXXX")" || { warn 'Konsole: no se pudo crear un temporal seguro.'; return 0; }
  if ! curl -fL --proto '=https' --tlsv1.2 -o "$downloaded" "$source_url" || [[ "$(sha256_stream < "$downloaded")" != "$expected_sha256" ]]; then
    rm -f -- "$downloaded"
    warn 'Konsole: no se pudo descargar o verificar Dracula.colorscheme; no se modificó nada.'
    return 0
  fi
  validate_target_containment '.local/share/konsole/Dracula.colorscheme'
  validate_target_containment '.local/share/konsole/Dotfiles.profile'
  validate_target_containment '.config/konsolerc'
  mkdir -p "$scheme_dir" "${konsolerc%/*}"
  if [[ ! -e "$scheme" && ! -L "$scheme" ]]; then
    install_tmp="$(mktemp "$scheme_dir/.Dracula.colorscheme.dotfiles.XXXXXX")" || { rm -f -- "$downloaded"; die 'Konsole: no se pudo preparar la instalación atómica del esquema.'; }
    if ! cp "$downloaded" "$install_tmp" || ! chmod 644 "$install_tmp" || ! mv -f "$install_tmp" "$scheme"; then
      rm -f -- "$downloaded" "$install_tmp"
      die 'Konsole: no se pudo instalar Dracula.colorscheme.'
    fi
  fi
  rm -f -- "$downloaded"
  profile_tmp="$(mktemp "$scheme_dir/.Dotfiles.profile.dotfiles.XXXXXX")" || die 'Konsole: no se pudo preparar el perfil.'
  printf '[Appearance]\nColorScheme=Dracula\nFont=%s,10,-1,5,50,0,0,0,0,0\n\n[General]\nName=Dotfiles\n' "$font_family" > "$profile_tmp"
  chmod 644 "$profile_tmp"
  mv -f "$profile_tmp" "$profile_file" || { rm -f -- "$profile_tmp"; die 'Konsole: no se pudo instalar Dotfiles.profile.'; }
  config_tmp="$(mktemp "${konsolerc%/*}/.konsolerc.dotfiles.XXXXXX")" || die 'Konsole: no se pudo preparar konsolerc.'
  write_konsole_default_profile "$konsolerc" "$konsolerc" "$config_tmp" || { rm -f -- "$config_tmp"; die 'Konsole: no se pudo actualizar el perfil predeterminado.'; }
  mark_path_if_changed '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
  mark_path_if_changed '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
  mark_path_if_changed '.config/konsolerc' konsole_config '-'
  success 'Konsole configurado con Dracula y MesloLGS Nerd Font para nuevas ventanas/sesiones.'
}
install_nerd_font() {
  local font_dir tmp_dir name target before fingerprint expected url downloaded font_state font_family
  local base_url='https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.5.1/patched-fonts/Meslo/S'
  local -a missing_fonts=()
  [[ "${DOTFILES_SKIP_FONT:-0}" != 1 ]] || { info 'Fuente omitida por el entorno de pruebas.'; return 0; }
  IFS=$'\t' read -r font_state font_family < <(meslo_nerd_font_resolution)
  if [[ "$font_state" == system ]]; then
    MESLO_FONT_FAMILY="$font_family"; MESLO_FONT_ORIGIN=system
    success "$font_family ya está disponible mediante fontconfig; se conserva como externa."
    return 0
  fi
  if [[ "$DOTFILES_OS" == macos ]]; then
    if brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1; then
      [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] && ! grep -q '^homebrew-cask:' "$ACTIVE_CYCLE_DIR/fonts.tsv" && printf 'homebrew-cask:font-meslo-lg-nerd-font\talready_present\t-\n' >> "$ACTIVE_CYCLE_DIR/fonts.tsv"
      MESLO_FONT_FAMILY='MesloLGS Nerd Font'; MESLO_FONT_ORIGIN=system
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
  if font_family="$(meslo_nerd_font_family)"; then MESLO_FONT_FAMILY="$font_family"; else MESLO_FONT_FAMILY='MesloLGS Nerd Font'; fi
  MESLO_FONT_ORIGIN=managed
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
  local settings_dir backup="${3:-$settings_target.pre-dotfiles}" label="${4:-settings.json}" temporary mode
  settings_dir="${settings_target%/*}"
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
      success "VS Code: $label ya está actualizado."
      return 0
    fi
    if [[ "$backup" != - && ! -e "$backup" && ! -L "$backup" ]] && ! cp -p "$settings_target" "$backup"; then
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
  success "VS Code: $label gestionado y validado."
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
  local profile="$1" settings_source settings_dir settings_target locale_source locale_target extension installed_extensions extension_name
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
  locale_source="$(mktemp)" || { warn 'VS Code: no se pudo preparar locale.json.'; return 0; }
  printf '{"locale":"es"}\n' > "$locale_source"
  locale_target="$settings_dir/locale.json"
  if ! merge_vscode_settings "$locale_source" "$locale_target" - locale.json; then
    warn 'VS Code: locale.json no pudo configurarse; la instalación continúa.'
  fi
  rm -f -- "$locale_source"
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
  if privileged_chsh "$zsh_path"; then
    record_shell_changed "$zsh_path"
    success "Shell por defecto cambiado a $zsh_path"
    info 'El cambio será efectivo al iniciar una nueva sesión de usuario.'
    printf '  Para usar Zsh ahora en esta terminal: exec zsh\n'
  else warn "Ejecuta manualmente: chsh -s $zsh_path"; fi
}
