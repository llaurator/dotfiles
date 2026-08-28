# Personal profile
if [[ -d "$HOME/.pyenv" ]]; then
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"
fi
if [[ -d "$HOME/Android/Sdk" ]]; then
  export ANDROID_HOME="$HOME/Android/Sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$PATH:$ANDROID_HOME/platform-tools"
fi
[[ -d /opt/flutter/bin ]] && export PATH="$PATH:/opt/flutter/bin"
[[ -f /opt/miniconda3/etc/profile.d/conda.sh ]] && source /opt/miniconda3/etc/profile.d/conda.sh
command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias)"
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
