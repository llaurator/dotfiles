# Herramientas de desarrollo opcionales. Ninguna es requisito para abrir Zsh.
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="$(pyenv root)"
  [[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

if [[ -d "${ANDROID_SDK_ROOT:-}" ]]; then
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
elif [[ -d "${ANDROID_HOME:-}" ]]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
elif [[ -d "$HOME/Library/Android/sdk" ]]; then
  export ANDROID_HOME="$HOME/Library/Android/sdk"
elif [[ -d "$HOME/Android/Sdk" ]]; then
  export ANDROID_HOME="$HOME/Android/Sdk"
fi
if [[ -n "${ANDROID_HOME:-}" ]]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  [[ -d "$ANDROID_HOME/platform-tools" ]] && export PATH="$PATH:$ANDROID_HOME/platform-tools"
fi

[[ -d "$HOME/flutter/bin" ]] && export PATH="$PATH:$HOME/flutter/bin"
[[ -d /opt/flutter/bin ]] && export PATH="$PATH:/opt/flutter/bin"
if [[ -r "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [[ -r /opt/miniconda3/etc/profile.d/conda.sh ]]; then
  source /opt/miniconda3/etc/profile.d/conda.sh
fi

if command -v java >/dev/null 2>&1; then
  if [[ "$OSTYPE" == darwin* && -x /usr/libexec/java_home ]]; then
    _dotfiles_java_home="$(/usr/libexec/java_home 2>/dev/null || true)"
  elif command -v readlink >/dev/null 2>&1; then
    _dotfiles_java_bin="$(readlink -f "$(command -v java)" 2>/dev/null || true)"
    [[ -n "$_dotfiles_java_bin" ]] && _dotfiles_java_home="${_dotfiles_java_bin:h:h}"
  fi
  [[ -n "${_dotfiles_java_home:-}" && -d "$_dotfiles_java_home" ]] && export JAVA_HOME="$_dotfiles_java_home"
  unset _dotfiles_java_bin _dotfiles_java_home
fi

command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias)"
