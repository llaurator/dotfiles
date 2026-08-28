export ZSH="$HOME/.oh-my-zsh"
export BAT_THEME="Dracula"
export PATH="$HOME/.local/bin:$PATH"

if [[ -d "$ZSH" ]]; then
  plugins=(git colored-man-pages extract sudo zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)
  source "$ZSH/oh-my-zsh.sh"
fi

P10K_THEME="$HOME/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme"
[[ -f "$P10K_THEME" ]] && source "$P10K_THEME"
unset P10K_THEME

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

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="
    --layout=reverse
    --color=fg:#F8F8F2,bg:#282A36,hl:#BD93F9
    --color=fg+:#F8F8F2,bg+:#44475A,hl+:#FF79C6
    --color=info:#FFB86C,prompt:#50FA7B,pointer:#FF79C6
    --color=marker:#FF79C6,spinner:#F1FA8C,header:#6272A4
  "
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {} 2>/dev/null'"
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
