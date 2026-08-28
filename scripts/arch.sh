#!/usr/bin/env bash
install_system_packages(){ sudo pacman -Syu --needed --noconfirm git stow zsh fzf fd zoxide eza bat ripgrep btop grc git-delta direnv; }
