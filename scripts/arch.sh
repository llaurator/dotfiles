#!/usr/bin/env bash
install_system_packages() {
  local packages=(git stow zsh jq fzf fd zoxide eza bat ripgrep btop grc git-delta direnv)
  [[ "$PROFILE" == server ]] || packages+=(code)
  sudo pacman -S --needed --noconfirm "${packages[@]}"
}
