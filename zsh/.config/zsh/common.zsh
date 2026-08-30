export BAT_THEME="Dracula"
export PATH="$HOME/.local/bin:$PATH"

DOTFILES_ZSH_COMPONENTS_FILE="$HOME/.config/dotfiles/zsh-components.zsh"
[[ -r "$DOTFILES_ZSH_COMPONENTS_FILE" ]] && source "$DOTFILES_ZSH_COMPONENTS_FILE"
unset DOTFILES_ZSH_COMPONENTS_FILE
[[ -n "${ZSH:-}" ]] || export ZSH="$HOME/.oh-my-zsh"

if [[ -n "${ZSH:-}" && -r "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME=""
  plugins=(git colored-man-pages extract sudo)
  source "$ZSH/oh-my-zsh.sh"
fi

[[ -r "${DOTFILES_P10K_THEME:-}" ]] && source "$DOTFILES_P10K_THEME"
[[ -r "${DOTFILES_ZSH_AUTOSUGGESTIONS:-}" ]] && source "$DOTFILES_ZSH_AUTOSUGGESTIONS"
[[ -r "${DOTFILES_ZSH_HISTORY_SUBSTRING:-}" ]] && source "$DOTFILES_ZSH_HISTORY_SUBSTRING"
# zsh-syntax-highlighting debe ser el último plugin externo.
[[ -r "${DOTFILES_ZSH_SYNTAX_HIGHLIGHTING:-}" ]] && source "$DOTFILES_ZSH_SYNTAX_HIGHLIGHTING"

HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY INC_APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_FIND_NO_DUPS HIST_EXPIRE_DUPS_FIRST HIST_REDUCE_BLANKS HIST_IGNORE_SPACE

zshaddhistory() {
  local j=1 words
  words=(${(z)1})
  while [[ ${words[$j]} == *=* ]]; do ((j++)); done
  [[ -n ${words[$j]} ]] || return 1
  whence ${words[$j]} >/dev/null 2>&1 || return 1
}

if (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi

if command -v fzf >/dev/null 2>&1; then
  if fzf --help 2>&1 | command grep -q -- '--zsh'; then
    source <(fzf --zsh)
  elif [[ -r /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    [[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
  elif [[ -r /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]]; then
    source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
    [[ -r /opt/homebrew/opt/fzf/shell/completion.zsh ]] && source /opt/homebrew/opt/fzf/shell/completion.zsh
  fi
  export FZF_DEFAULT_OPTS="
    --layout=reverse
    --color=fg:#F8F8F2,bg:#282A36,hl:#BD93F9
    --color=fg+:#F8F8F2,bg+:#44475A,hl+:#FF79C6
    --color=info:#FFB86C,prompt:#50FA7B,pointer:#FF79C6
    --color=marker:#FF79C6,spinner:#F1FA8C,header:#6272A4
  "
  if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null'"
  fi
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
fi

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"

if command -v grc >/dev/null 2>&1; then
  GRC_DIR=""
  if [[ -d /usr/share/grc ]]; then
    GRC_DIR=/usr/share/grc
  elif command -v brew >/dev/null 2>&1; then
    BREW_GRC="$(brew --prefix grc 2>/dev/null)/share/grc"
    [[ -d "$BREW_GRC" ]] && GRC_DIR="$BREW_GRC"
    unset BREW_GRC
  fi
  if [[ -n "$GRC_DIR" ]]; then
    for conf in "$GRC_DIR"/conf.*(N); do
      cmd="${conf:t}"; cmd="${cmd#conf.}"
      command -v "$cmd" >/dev/null 2>&1 && alias "$cmd"="grc --colour=auto $cmd"
    done
  fi
  unset GRC_DIR conf cmd
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --group-directories-first --git --header'
  alias la='eza -a --icons=auto --group-directories-first'
  alias lt='eza --tree --icons=auto --group-directories-first --level=2'
  alias lta='eza --tree --icons=auto --group-directories-first --level=3 -a'
  alias tree='eza --tree --icons=auto --group-directories-first'
fi
if command -v bat >/dev/null 2>&1; then alias b='bat'; alias bp='bat --plain'; alias catp='bat --plain'; fi
if command -v rg >/dev/null 2>&1; then alias rgf='rg --files'; alias rgi='rg -i'; alias rgh='rg --hidden'; alias rga='rg --hidden --glob "!.git/*"'; fi
alias c='clear'
alias h='history'
alias gcl='git clone --depth 1'
alias gi='git init'
alias ga='git add'
alias gc='git commit -m'
alias cb='git checkout'
