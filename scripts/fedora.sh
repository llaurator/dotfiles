#!/usr/bin/env bash
install_system_packages() {
  local package
  get_system_packages
  sudo dnf install -y "${SYSTEM_REQUIRED_PACKAGES[@]}"
  for package in "${SYSTEM_OPTIONAL_PACKAGES[@]}"; do
    if ! sudo dnf install -y "$package"; then
      warn "Paquete opcional no disponible mediante dnf: $package"
    fi
  done
  if ! command_exists fd && command_exists fdfind; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  if [[ "$PROFILE" != server ]] && ! command_exists code; then
    warn 'VS Code no está en los repositorios Fedora estándar; se configurará cuando el comando code exista.'
  fi
}
# shellcheck disable=SC2034 # Consumida por scripts/state.sh después de source.
get_system_packages() { SYSTEM_REQUIRED_PACKAGES=(git stow zsh jq); SYSTEM_OPTIONAL_PACKAGES=(fzf fd-find zoxide eza bat ripgrep btop grc direnv); SYSTEM_PACKAGES=("${SYSTEM_REQUIRED_PACKAGES[@]}" "${SYSTEM_OPTIONAL_PACKAGES[@]}"); }
