#!/usr/bin/env bash
install_system_packages(){ command -v brew >/dev/null 2>&1 || die 'Homebrew no está instalado.'; brew install git stow zsh fzf fd zoxide eza bat ripgrep btop grc git-delta direnv; }
