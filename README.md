# dotfiles
polski's dotfiles

## New Mac

```bash
git clone https://github.com/polskiTran/dotfiles.git ~/Documents/GitHub/dotfiles
~/Documents/GitHub/dotfiles/bootstrap.sh
```

Installs everything in the [Brewfile](Brewfile), the tools Homebrew doesn't cover, and links the config files. Never replaces existing files and is safe to re-run.

## Adding software

Add it to the Brewfile instead of running `brew install`, then run `brew bundle`.
