# macOS-specific settings. Se carga antes de common.zsh.
if [[ -x /opt/homebrew/bin/brew ]]; then
  _dotfiles_brew=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  _dotfiles_brew=/usr/local/bin/brew
else
  _dotfiles_brew="$(command -v brew 2>/dev/null)"
fi
if [[ -n "${_dotfiles_brew:-}" ]]; then
  eval "$("$_dotfiles_brew" shellenv)"
fi
unset _dotfiles_brew
alias ports='lsof -i -P -n | grep LISTEN'
