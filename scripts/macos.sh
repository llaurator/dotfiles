#!/usr/bin/env bash
install_system_packages() {
  local brew_bin
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_bin=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_bin=/usr/local/bin/brew
  else
    brew_bin="$(command -v brew || true)"
  fi
  [[ -n "$brew_bin" ]] || die 'Homebrew no está instalado.'
  eval "$("$brew_bin" shellenv)"
  get_system_packages
  brew install "${SYSTEM_FORMULAE[@]}"
  if [[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]] && ! command_exists code; then
    brew install --cask visual-studio-code
  fi
}
get_system_packages() { SYSTEM_FORMULAE=(git stow jq fzf fd zoxide eza bat ripgrep btop grc git-delta direnv); SYSTEM_PACKAGES=("${SYSTEM_FORMULAE[@]}"); if [[ "$REQUEST_INSTALL_VSCODE" -eq 1 ]]; then SYSTEM_PACKAGES+=(visual-studio-code); fi; }
