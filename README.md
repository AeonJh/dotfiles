# MyDotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/).

## What is managed

- shell: zsh env entrypoint and private env loading
- editor: external Neovim config plus first-run bootstrap
- terminal: tmux + TPM, starship
- Claude Code: settings template, statusline hook, helper scripts
- private data: encrypted with age

Source root is `home/` via `.chezmoiroot`.

## Requirements

- `chezmoi`
- `git`
- `age` identity at `~/.config/chezmoi/age.txt`
- optional tools used by managed configs: `zsh`, `nvim`, `tmux`, `jq`, `curl`

## Bootstrap new machine

```bash
chezmoi init <repo>
install -d -m 700 ~/.config/chezmoi
install -m 600 /path/to/age.txt ~/.config/chezmoi/age.txt
chezmoi apply
```

First apply may clone external zsh/nvim/tmux plugin repos. Neovim bootstrap runs once, then writes a marker under `~/.local/state/chezmoi/`.

## Daily commands

```bash
chezmoi status          # see pending changes
chezmoi diff            # preview rendered changes
chezmoi apply           # apply dotfiles
chezmoi apply --refresh-externals
chezmoi edit ~/.zshenv  # edit managed file
chezmoi cd              # jump to source repo
```

## Private data

Private values live in encrypted source:

```text
home/.chezmoitemplates/private.toml.age
```

Used for:

- git identity
- private repo URLs
- shell env secrets rendered to `~/.config/shell/private-env.sh`

Never commit:

- `~/.config/chezmoi/age.txt`
- decrypted private TOML
- real tokens, API keys, account IDs, private repo URLs

Age usage and key rotation notes: [English](docs/AGE_ENCRYPTION_GUIDE.md) ([中文](docs/AGE_ENCRYPTION_GUIDE.zh-CN.md)).

## Layout

```text
home/.chezmoi.toml.tmpl                 chezmoi config template
home/.chezmoidata/                      public defaults and feature flags
home/.chezmoiexternals/                 external repo definitions
home/.chezmoiscripts/                   bootstrap/reload scripts
home/.chezmoitemplates/private.toml.age encrypted private data
home/dot_config/                        XDG config files
home/dot_claude/                        Claude Code config and helpers
```
