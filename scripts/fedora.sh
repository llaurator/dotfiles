#!/usr/bin/env bash
install_system_packages(){ sudo dnf install -y git stow zsh fzf fd-find zoxide eza bat ripgrep btop grc direnv; if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then mkdir -p "$HOME/.local/bin"; ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"; fi; }
