#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; TEST_ROOT="$(mktemp -d)"; trap 'rm -rf "$TEST_ROOT"' EXIT
HOME="$TEST_ROOT/home"; export HOME; DOTFILES_ZSH_SYSTEM_ROOT="$TEST_ROOT/system"; export DOTFILES_ZSH_SYSTEM_ROOT
XDG_STATE_HOME="$TEST_ROOT/state"; export XDG_STATE_HOME
source "$ROOT_DIR/scripts/lib.sh"; source "$ROOT_DIR/scripts/state.sh"; source "$ROOT_DIR/scripts/zsh_components.sh"; source "$ROOT_DIR/scripts/common.sh"
DOTFILES_DISTRO=arch
fail(){ printf 'FAIL: %s\n' "$1" >&2; exit 1; }
make_component(){ local base="$1" component="$2" marker; marker="$(zsh_component_marker "$component")"; mkdir -p "$base"; : > "$base/$marker"; }
assert_state(){ local component="$1" expected="$2" got; got="$(resolve_zsh_component "$component" | cut -f1)"; [[ "$got" == "$expected" ]] || fail "$component: $got != $expected"; }
state_snapshot(){ [[ -e "$XDG_STATE_HOME" ]] && find "$XDG_STATE_HOME" -printf '%P:%y:%s\n' | LC_ALL=C sort || printf 'missing\n'; }
create_active_baseline(){
  local cycle='20260831T120000Z-1' directory
  directory="$XDG_STATE_HOME/dotfiles/cycles/$cycle"
  mkdir -p "$directory"
  printf '%s\n' "$cycle" > "$XDG_STATE_HOME/dotfiles/active"
  printf 'format_version\t2\ninstallation_id\t%s\nhome\t%s\nprofile\tserver\nrepo\t%s\ncommit\ttest\ncreated_at\t2026-08-31T12:00:00Z\n' "$cycle" "$HOME" "$ROOT_DIR" > "$directory/metadata.tsv"
  printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$directory/manifest.tsv"
  printf 'relative_path\tkind\tproof\tsource\n' > "$directory/ownership.tsv"
  printf 'key\tbefore\tafter\n' > "$directory/environment.tsv"
  printf 'package\tmanager\tstate\n' > "$directory/packages.tsv"
  printf 'relative_path\texisted_before\ttype\tmode\tinstalled_mode\n' > "$directory/directories.tsv"
  printf 'relative_path\tbefore_fingerprint\tinstalled_fingerprint\n' > "$directory/fonts.tsv"
  mkdir -p "$directory/package-snapshots"
  printf 'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256\n' > "$directory/package-transactions.tsv"
  printf 'active\n' > "$directory/status"
}
mkdir -p "$HOME"
for c in omz p10k autosuggestions syntax history; do assert_state "$c" missing; done
make_component "$HOME/.oh-my-zsh" omz
assert_state omz external
git -C "$HOME/.oh-my-zsh" init -q; git -C "$HOME/.oh-my-zsh" config user.email test@example.invalid; git -C "$HOME/.oh-my-zsh" config user.name Test
git -C "$HOME/.oh-my-zsh" add oh-my-zsh.sh; git -C "$HOME/.oh-my-zsh" commit -qm baseline
git -C "$HOME/.oh-my-zsh" remote add origin https://github.com/ohmyzsh/ohmyzsh.git
create_active_baseline
printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\nOh My Zsh\t.oh-my-zsh\tno\thttps://github.com/ohmyzsh/ohmyzsh.git\t%s\n' "$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD)" > "$XDG_STATE_HOME/dotfiles/cycles/20260831T120000Z-1/upstream.tsv"
state_before="$(state_snapshot)"; assert_state omz managed; [[ "$state_before" == "$(state_snapshot)" ]] || fail 'la consulta de ownership escribió en STATE'
make_component "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" p10k
assert_state p10k external
rm -rf "$HOME/.oh-my-zsh"; mkdir -p "$TEST_ROOT/external"
for c in omz p10k autosuggestions syntax history; do make_component "$TEST_ROOT/external/$c" "$c"; done
cat > "$HOME/.zshrc" <<EOF
ZSH="\$HOME/../external/omz"
source "\$HOME/../external/p10k/powerlevel10k.zsh-theme"
. \${HOME}/../external/autosuggestions/zsh-autosuggestions.zsh
source $TEST_ROOT/external/syntax/zsh-syntax-highlighting.zsh
source $TEST_ROOT/external/history/zsh-history-substring-search.zsh
EOF
for c in omz p10k autosuggestions syntax history; do assert_state "$c" external; done
malicious="$TEST_ROOT/NO_DEBE_EXISTIR"
# shellcheck disable=SC2016 # Fixture malicioso que debe permanecer literal.
printf 'ZSH="$(touch %s)"\nsource /missing/zsh-autosuggestions.zsh\n' "$malicious" > "$HOME/.zshrc"
assert_state omz missing; assert_state autosuggestions missing; [[ ! -e "$malicious" ]] || fail 'se ejecutó .zshrc'
for value in "\$HOME/path" "\${HOME}/path"; do [[ "$(zsh_safe_path "$value")" == "$HOME/path" ]] || fail "expansión HOME inválida: $value"; done
command_substitution="\$(touch $TEST_ROOT/no-debe-ejecutarse)"
for value in "\$HOMEfoo/path" "\${HOMEfoo}/path" "$command_substitution"; do zsh_safe_path "$value" >/dev/null && fail "se aceptó una expresión insegura: $value"; done
[[ ! -e "$TEST_ROOT/no-debe-ejecutarse" ]] || fail 'se ejecutó una sustitución de comando'
rm -f "$HOME/.zshrc"; make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/oh-my-zsh" omz; make_component "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/zsh/plugins/zsh-syntax-highlighting" syntax
assert_state omz external; assert_state syntax external
mkdir -p "$DOTFILES_ZSH_SYSTEM_ROOT/usr/share/zsh/plugins/zsh-autosuggestions"; assert_state autosuggestions missing
before="$(find "$HOME" -printf '%P\n' | sort)"; state_before="$(state_snapshot)"; CONFLICT_RELS=(); get_system_packages(){ SYSTEM_PACKAGES=(); }; print_install_preflight server > "$TEST_ROOT/out"; [[ "$before" == "$(find "$HOME" -printf '%P\n' | sort)" ]] || fail 'preflight escribió en HOME'; [[ "$state_before" == "$(state_snapshot)" ]] || fail 'preflight escribió en STATE'
printf 'OK: resolución read-only y segura de componentes Zsh\n'
