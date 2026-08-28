#!/usr/bin/env bash
install_system_packages() {
  local package
  local optional_packages=(fzf fd-find zoxide eza bat ripgrep btop grc direnv)
  sudo dnf install -y git stow zsh
  for package in "${optional_packages[@]}"; do
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
