# Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_CONFIG="$HOME/.config/zsh"
DOTFILES_PROFILE_FILE="$HOME/.config/dotfiles/profile"

case "$OSTYPE" in
  darwin*) [[ -f "$ZSH_CONFIG/macos.zsh" ]] && source "$ZSH_CONFIG/macos.zsh" ;;
  linux*)  [[ -f "$ZSH_CONFIG/linux.zsh" ]] && source "$ZSH_CONFIG/linux.zsh" ;;
esac

[[ -f "$ZSH_CONFIG/common.zsh" ]] && source "$ZSH_CONFIG/common.zsh"

if [[ -f "$DOTFILES_PROFILE_FILE" ]]; then
  DOTFILES_PROFILE="$(<"$DOTFILES_PROFILE_FILE")"
  case "$DOTFILES_PROFILE" in
    personal) [[ -f "$ZSH_CONFIG/personal.zsh" ]] && source "$ZSH_CONFIG/personal.zsh" ;;
    work)     [[ -f "$ZSH_CONFIG/work.zsh" ]] && source "$ZSH_CONFIG/work.zsh" ;;
    server)   [[ -f "$ZSH_CONFIG/server.zsh" ]] && source "$ZSH_CONFIG/server.zsh" ;;
  esac
fi

[[ -r "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
unset ZSH_CONFIG DOTFILES_PROFILE DOTFILES_PROFILE_FILE
