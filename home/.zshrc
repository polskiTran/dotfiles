# load zprof to profile zsh startup
# zmodload zsh/zprof
# put this at the end of your .zshrc
# zprof

# ======= PATH EXPORTS & ENV ===========
# openjdk
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export PATH="$JAVA_HOME/bin:$PATH"
# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/polski/.lmstudio/bin"
# End of LM Studio CLI section

# ======= END FUN STUFF ===========

export PATH="$HOME/.local/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/polski/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# case insensitive
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# bun completions
[ -s "/Users/polski/.bun/_bun" ] && source "/Users/polski/.bun/_bun"

# ======= RUST BINARIES ===========
# starship prompt
export STARSHIP_CONFIG=~/.config/starship.toml
eval "$(starship init zsh)"
# zoxide
eval "$(zoxide init zsh)"
# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)


# ======= ALIASES ===========
# alias. option: --no-permissions --no-user
alias ls="eza --long --color=always --icons=always --no-permissions --no-user"
alias lsa="eza --long --color=always --icons=always --no-permissions -alh"
# alias lst="eza --long --color=always --icons=always --no-permissions -T -L 4"
# replace alias with function for lst dynamic arguments
# unalias lst
lst() {
  eza --long --color=always --icons=always --no-permissions -T -L "${1:-2}"
}
# ======= END ALIASES ===========

# ======= LAZY NVM ===========
lazynvm() {
  unset -f nvm node npm npx pi
  export NVM_DIR=~/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" # This loads nvm
  if [ -f "$NVM_DIR/bash_completion" ]; then
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
  fi
}

nvm() {
  lazynvm
  nvm $@
}

pi() {
  lazynvm
  pi $@
}

node() {
  lazynvm
  node $@
}

npm() {
  lazynvm
  npm $@
}

npx() {
  lazynvm
  npx $@
}
# ======= END LAZY NVM ===========

# ======= FUN STUFF ===========
# auto cast fastfetch for fun lmao
# fastfetch
echo "keep it up. dont give up. keep going"

# ======= PLUGINS (MUST BE LAST) ===========
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# source ~/.zsh/zsh-autocomplete/zsh-autocomplete.plugin.zsh
