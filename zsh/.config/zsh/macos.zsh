# macOS-specific settings
if command -v brew >/dev/null 2>&1; then eval "$(brew shellenv)"; fi
alias ports='lsof -i -P -n | grep LISTEN'
