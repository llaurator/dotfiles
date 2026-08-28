# Linux-specific settings
export LESS='-R --use-color -Dd+r$Du+b'
if dd --help 2>&1 | grep -q -- 'status='; then alias dd='dd status=progress'; fi
alias scp='noglob scp'
alias sudo='sudo -v; sudo '
