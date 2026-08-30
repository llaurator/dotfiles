#!/usr/bin/env bash
get_system_packages() { SYSTEM_PACKAGES=(git stow zsh jq fzf fd zoxide eza bat ripgrep btop grc git-delta direnv); if [[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]]; then SYSTEM_PACKAGES+=(code); fi; }
install_system_packages() { get_system_packages; run_tracked_package_transaction system-packages run_privileged pacman -S --needed --noconfirm "${SYSTEM_PACKAGES[@]}"; }
