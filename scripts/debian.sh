#!/usr/bin/env bash
install_system_packages() {
  local package
  local optional_packages=(fzf fd-find zoxide bat ripgrep btop grc direnv eza)
  local available_packages=()
  sudo apt-get update
  sudo apt-get install -y git stow zsh jq
  for package in "${optional_packages[@]}"; do
    if apt-cache show --no-all-versions "$package" >/dev/null 2>&1; then
      available_packages+=("$package")
    else
      warn "Paquete no disponible mediante apt: $package"
    fi
  done
  if (( ${#available_packages[@]} )); then
    sudo apt-get install -y "${available_packages[@]}"
  fi
  mkdir -p "$HOME/.local/bin"
  if ! command_exists fd && command_exists fdfind; then
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  if ! command_exists bat && command_exists batcat; then
    ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
  command_exists eza || warn 'eza no está disponible en esta versión de apt; se conservará ls.'
  if [[ "$PROFILE" != server ]] && ! command_exists code; then
    warn 'VS Code no está en los repositorios Debian/Ubuntu estándar; se configurará cuando el comando code exista.'
  fi
}
