#!/usr/bin/env bash
install_system_packages() {
  local package
  get_system_packages
  run_tracked_package_transaction system-required run_privileged dnf install -y "${SYSTEM_REQUIRED_PACKAGES[@]}"
  for package in "${SYSTEM_OPTIONAL_PACKAGES[@]}"; do
    if ! run_tracked_package_transaction "optional-$package" run_privileged dnf install -y "$package"; then
      warn "Paquete opcional no disponible mediante dnf: $package"
    fi
  done
  if ! command_exists fd && command_exists fdfind; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  if [[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]] && ! command_exists code; then install_fedora_vscode; fi
}

install_fedora_vscode() {
  local repo_file="$FEDORA_VSCODE_REPO_FILE" repo_tmp key_tmp key_checksum
  command_exists curl || die 'Se necesita curl para configurar el repositorio oficial de VS Code.'
  record_fedora_vscode_repository_before
  if [[ -e "$repo_file" || -L "$repo_file" ]]; then
    [[ -f "$repo_file" && ! -L "$repo_file" ]] || die "El fichero de repositorio de VS Code es inseguro: $repo_file"
    if ! grep -Eq '^baseurl=https://packages\.microsoft\.com/yumrepos/vscode$' "$repo_file" ||
       ! grep -Eq '^gpgkey=https://packages\.microsoft\.com/keys/microsoft\.asc$' "$repo_file" ||
       ! grep -Eq '^gpgcheck=1$' "$repo_file"; then
      die "El repositorio preexistente de VS Code no coincide con el origen oficial de Microsoft: $repo_file"
    fi
  else
    repo_tmp="$(mktemp)" || die 'No se pudo preparar el repositorio de VS Code.'
    printf '%s\n' \
      '[code]' \
      'name=Visual Studio Code' \
      'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
      'enabled=1' \
      'autorefresh=1' \
      'type=rpm-md' \
      'gpgcheck=1' \
      'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' > "$repo_tmp"
    chmod 644 "$repo_tmp"
    run_privileged install -o root -g root -m 0644 "$repo_tmp" "$repo_file" || { rm -f -- "$repo_tmp"; die 'No se pudo instalar el repositorio oficial de VS Code.'; }
    rm -f -- "$repo_tmp"
  fi
  record_fedora_vscode_repository_after

  key_tmp="$(mktemp)" || die 'No se pudo preparar la clave de Microsoft.'
  if ! curl -fL --proto '=https' --tlsv1.2 -o "$key_tmp" 'https://packages.microsoft.com/keys/microsoft.asc'; then
    rm -f -- "$key_tmp"
    die 'No se pudo descargar la clave oficial de Microsoft.'
  fi
  key_checksum="$(sha256_stream < "$key_tmp")"
  if [[ "$key_checksum" != '2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6' ]]; then
    rm -f -- "$key_tmp"
    die 'La clave oficial de Microsoft no coincide con la huella fijada.'
  fi
  run_privileged rpm --import "$key_tmp" || { rm -f -- "$key_tmp"; die 'No se pudo importar la clave oficial de Microsoft.'; }
  rm -f -- "$key_tmp"
  run_tracked_package_transaction vscode run_privileged dnf install -y code
}
# shellcheck disable=SC2034 # Consumida por scripts/state.sh después de source.
get_system_packages() { SYSTEM_REQUIRED_PACKAGES=(git stow zsh jq); SYSTEM_OPTIONAL_PACKAGES=(fzf fd-find zoxide eza bat ripgrep btop grc direnv); SYSTEM_PACKAGES=("${SYSTEM_REQUIRED_PACKAGES[@]}" "${SYSTEM_OPTIONAL_PACKAGES[@]}"); if [[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]]; then SYSTEM_PACKAGES+=(code); fi; }
