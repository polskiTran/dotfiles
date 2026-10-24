
# ============================================================
# ZSH CONFIGURATION — macOS / Apple Silicon
# ============================================================

# ======= OPTIONAL STARTUP PROFILING =======
# Uncomment both lines to profile shell startup.
zmodload zsh/zprof


# ======= ENVIRONMENT & PATH =======

# Deduplicate PATH while preserving first-match priority.
typeset -U path

# Java / OpenJDK 21
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"

# Bun
export BUN_INSTALL="$HOME/.bun"

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"

# NVM (initialized lazily below)
export NVM_DIR="$HOME/.nvm"

# PATH priority: pnpm > local > bun > Java > existing PATH
path=(
  "$PNPM_HOME/bin"
  "$HOME/.local/bin"
  "$BUN_INSTALL/bin"
  "$JAVA_HOME/bin"
  $path
  "$HOME/.lmstudio/bin"
)

export PATH


# ======= COMPLETION SYSTEM =======

# Initialize Zsh completions with standard security checks.
autoload -Uz compinit
compinit

# Case-insensitive tab completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Bun completions
if [[ -r "$BUN_INSTALL/_bun" ]]; then
  source "$BUN_INSTALL/_bun"
fi


# ======= RUST CLI TOOLS =======

# Starship prompt
export STARSHIP_CONFIG="$HOME/.config/starship.toml"

if (( $+commands[starship] )); then
  eval "$(command starship init zsh)"
fi

# Zoxide directory navigation
if (( $+commands[zoxide] )); then
  eval "$(command zoxide init zsh)"
fi

# fzf key bindings and fuzzy completion
if (( $+commands[fzf] )); then
  source <(command fzf --zsh)
fi


# ======= FILE & DIRECTORY ALIASES =======

alias ls='eza --long --color=auto --icons=auto --no-permissions --no-user'
alias lsa='eza --long --color=auto --icons=auto --no-permissions -alh'

# Tree listing with configurable depth (default: 2)
lst() {
  local depth="${1:-2}"
  eza --long --color=auto --icons=auto \
    --no-permissions -T -L "$depth"
}


# ======= AGENT SANDBOX ALIASES =======

# Herdr agent: Pi
alias pihn='HERDR_AGENT=pi sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/pi-kit/" -m 8gb'
alias pih='HERDR_AGENT=pi sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/pi-kit/"'

# Herdr agent: Claude
alias claudehn='HERDR_AGENT=claude sbx run claude --kit "$HOME/Documents/GitHub/dotfiles/agent-kits/claude-kit/" -m 8gb'
alias claudeh='HERDR_AGENT=claude sbx run claude'

# Herdr agent: OMP
alias omphn='HERDR_AGENT=omp sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/omp-kit/" -m 8gb'
alias omph='HERDR_AGENT=omp sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/omp-kit/"'


# ======= SANDBOX ALIASES =======

# Pi
alias pi-new-sbx='sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/pi-kit/" -m 8gb'
alias pi-sbx='sbx run "$HOME/Documents/GitHub/dotfiles/agent-kits/pi-kit/"'

# Claude
alias claude-new-sbx='sbx run claude --kit "$HOME/Documents/GitHub/dotfiles/agent-kits/claude-kit/" -m 8gb'
alias claude-sbx='sbx run claude'


# ======= LAZY NVM =======

# Load NVM only on the first invocation of:
# nvm, node, npm, npx, or pi.
#
# This avoids NVM startup overhead for shells that do not
# require Node.js.

lazynvm() {
  local nvm_script="$NVM_DIR/nvm.sh"

  if [[ ! -r "$nvm_script" ]]; then
    print -u2 "NVM initialization failed: $nvm_script"
    return 1
  fi

  # Remove wrappers before sourcing to avoid recursive calls.
  unfunction nvm node npm npx pi 2>/dev/null

  # Initialize NVM and its default version selection.
  source "$nvm_script" || {
    print -u2 "Failed to initialize NVM"
    return 1
  }
}

nvm() {
  lazynvm || return 1
  nvm "$@"
}

node() {
  lazynvm || return 1
  command node "$@"
}

npm() {
  lazynvm || return 1
  command npm "$@"
}

npx() {
  lazynvm || return 1
  command npx "$@"
}

pi() {
  lazynvm || return 1
  command pi "$@"
}


# ======= OPTIONAL STARTUP MESSAGE =======

# Uncomment to display a message on every interactive shell.
# print "keep it up. dont give up. keep going"


# ======= ZSH PLUGINS =======

# Autosuggestions
if [[ -r "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Syntax highlighting must remain last.
if [[ -r "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi


# ======= OPTIONAL STARTUP PROFILING =======
zprof

# ================= END ZSHRC =================
