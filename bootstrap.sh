#!/usr/bin/env bash
# Sets up a new Mac from this repo. Safe to re-run: existing files are never replaced.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Symlink $1 to $2, leaving anything already at $2 alone.
link() {
  if [[ -e "$2" || -L "$2" ]]; then
    [[ "$2" -ef "$1" ]] || echo "skip (already exists): $2"
    return 0
  fi
  mkdir -p "$(dirname "$2")"
  ln -s "$1" "$2"
  echo "linked: $2"
}

# Clone repo $1 into $2 unless it is already there.
clone() {
  [[ -d "$2" ]] || git clone --depth 1 "$1" "$2"
}

# ======= HOMEBREW =======
if ! command -v brew >/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# One failed package shouldn't stop the rest of the setup.
brew bundle --file="$DOTFILES/Brewfile" || echo "warning: some Brewfile entries failed" >&2

# ======= NOT ON HOMEBREW =======
if [[ ! -d "$HOME/.nvm" ]]; then
  git clone https://github.com/nvm-sh/nvm.git "$HOME/.nvm"
  git -C "$HOME/.nvm" checkout "$(git -C "$HOME/.nvm" describe --tags --abbrev=0)"
fi

clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/zsh-syntax-highlighting"

# ======= CONFIG FILES =======
link "$DOTFILES/home/.zshrc" "$HOME/.zshrc"
link "$DOTFILES/home/.tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/zed/settings.json" "$HOME/.config/zed/settings.json"
link "$DOTFILES/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"

for config in "$DOTFILES"/.config/*; do
  link "$config" "$HOME/.config/$(basename "$config")"
done
