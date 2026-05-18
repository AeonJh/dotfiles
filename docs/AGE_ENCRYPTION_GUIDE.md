# Age Encryption Guide

Language: English | [中文](AGE_ENCRYPTION_GUIDE.zh-CN.md)

This repository uses `age` through chezmoi to keep private dotfiles data in Git without storing secrets in plaintext.

The model is intentionally small:

- Public defaults stay in `.chezmoidata/`.
- Private template data is encrypted as one TOML file.
- The age identity stays outside the repository.
- Chezmoi handles encryption and decryption during normal operations.

## Repository layout

```text
home/.chezmoi.toml.tmpl                 chezmoi config template
home/.chezmoidata/                      public defaults and feature flags
home/.chezmoitemplates/private.toml.age encrypted private template data
home/.chezmoiexternals/                 templates that consume private data
home/.chezmoiignore                     local secrets excluded from management
```

The encrypted private data currently backs values such as:

- Git identity details
- private repository URLs
- private template variables

Do not put tokens, private keys, account IDs, or private repository URLs in Markdown, plain TOML, shell history, or command arguments.

## Core concepts

| Term | Meaning | Safe to commit? |
|---|---|---|
| recipient | Public age recipient used for encryption | Yes |
| identity | Private age key used for decryption | No |
| ciphertext | Encrypted `.age` file | Yes |
| plaintext | Decrypted secret content | No |

The local identity path is:

```text
~/.config/chezmoi/age.txt
```

Losing this file means existing ciphertext cannot be decrypted. Back it up outside this repository.

## Chezmoi configuration

The tracked config template enables age:

```toml
encryption = "age"
useBuiltinAge = true

[age]
identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/age.txt"
recipient = "<AGE_PUBLIC_RECIPIENT>"
```

`useBuiltinAge = true` keeps the dotfiles usable even when the external `age` CLI is not installed. Installing the CLI is still useful for ad hoc encryption outside chezmoi.

## Bootstrap a new machine

1. Install `chezmoi` and `git`.
2. Clone or initialize this dotfiles repository.
3. Restore the age identity from a password manager or offline backup.
4. Apply dotfiles.

```bash
chezmoi init <repo>
install -d -m 700 ~/.config/chezmoi
install -m 600 /path/to/age.txt ~/.config/chezmoi/age.txt
chezmoi apply
```

Verify permissions:

```bash
stat -c '%a %n' ~/.config/chezmoi ~/.config/chezmoi/age.txt
```

Expected shape:

```text
700 /home/<USER>/.config/chezmoi
600 /home/<USER>/.config/chezmoi/age.txt
```

## Daily operations

### Check encrypted data without printing it

```bash
chezmoi decrypt ~/.local/share/chezmoi/home/.chezmoitemplates/private.toml.age >/dev/null
```

### Render templates that depend on private data

```bash
repo="$HOME/.local/share/chezmoi"

chezmoi execute-template --file "$repo/home/.chezmoiexternals/nvim.toml.tmpl" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/zsh.toml.tmpl" >/dev/null
```

### Preview dotfile changes

Avoid printing private external URLs when not needed:

```bash
chezmoi diff --exclude=externals --refresh-externals=never
```

### Edit encrypted private template data

```bash
chezmoi edit-encrypted ~/.local/share/chezmoi/home/.chezmoitemplates/private.toml.age
```

Keep this file limited to template data. Use dedicated encrypted target files for larger secrets.

## Add encrypted target files

Use chezmoi's encrypted source-state support for files that should exist in the home directory after apply:

```bash
chezmoi add --encrypt ~/.ssh/config.private
chezmoi add --encrypt ~/.config/example/credentials.toml
```

Chezmoi stores ciphertext in the source tree and decrypts it when applying.

Prefer this for:

- private SSH config fragments
- API credential files
- application-specific secret config

Avoid this for:

- the age identity itself
- secrets better managed by a password manager
- high-churn data that changes constantly

## Manual age usage

Chezmoi can use built-in age, but the external CLI is useful outside the dotfiles workflow.

Install on Debian/Ubuntu:

```bash
sudo apt install age
```

Encrypt a file:

```bash
age -r <AGE_PUBLIC_RECIPIENT> -o secret.txt.age secret.txt
```

Decrypt to stdout:

```bash
age -d -i ~/.config/chezmoi/age.txt secret.txt.age
```

Encrypt a directory backup without leaving a plaintext archive:

```bash
tar -czf - ~/Documents/private/ \
  | age -r <AGE_PUBLIC_RECIPIENT> \
  -o private-documents.tar.gz.age
```

Restore it:

```bash
age -d -i ~/.config/chezmoi/age.txt private-documents.tar.gz.age \
  | tar -xzf -
```

## Key rotation

Rotate only when necessary: identity exposure, device retirement, recipient cleanup, or a planned migration.

Rule: decrypt with the old identity first, then encrypt with the new recipient. Do not overwrite the old identity until new ciphertext is verified.

### 1. Prepare a private workspace

```bash
repo="$HOME/.local/share/chezmoi"
tmpdir="$(mktemp -d)"
chmod 700 "$tmpdir"
```

### 2. Preserve the old identity

```bash
cp ~/.config/chezmoi/age.txt "$tmpdir/age.txt.old"
chmod 600 "$tmpdir/age.txt.old"
```

### 3. Decrypt current private data

```bash
chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" > "$tmpdir/private.toml"
chmod 600 "$tmpdir/private.toml"
```

### 4. Generate a new identity and recipient

```bash
chezmoi age-keygen -o "$tmpdir/age.txt.new"
chmod 600 "$tmpdir/age.txt.new"

new_recipient="$(chezmoi age-keygen -y "$tmpdir/age.txt.new")"
printf '%s\n' "$new_recipient"
```

### 5. Update chezmoi config

Edit `home/.chezmoi.toml.tmpl` and replace the recipient:

```toml
[age]
identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/age.txt"
recipient = "<NEW_AGE_PUBLIC_RECIPIENT>"
```

Install the new identity locally and regenerate config:

```bash
install -m 600 "$tmpdir/age.txt.new" ~/.config/chezmoi/age.txt
chezmoi init
```

### 6. Re-encrypt private data

```bash
chezmoi encrypt < "$tmpdir/private.toml" > "$tmpdir/private.toml.age"
mv "$tmpdir/private.toml.age" "$repo/home/.chezmoitemplates/private.toml.age"
```

For additional `.age` files, decrypt each file with the old identity before switching, then re-encrypt each file with the new recipient.

### 7. Verify

```bash
chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/nvim.toml.tmpl" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/zsh.toml.tmpl" >/dev/null
chezmoi diff --exclude=externals --refresh-externals=never >/dev/null
git diff --check
```

Only after successful verification:

```bash
rm -rf "$tmpdir"
```

## Safety checklist

Do:

- Back up `~/.config/chezmoi/age.txt` in a password manager or offline encrypted storage.
- Keep `~/.config/chezmoi` at mode `700`.
- Keep `~/.config/chezmoi/age.txt` at mode `600`.
- Commit ciphertext and public recipients only.
- Review diffs before committing encrypted workflow changes.

Do not:

- Commit `age.txt` or decrypted private TOML.
- Share the age identity.
- Store real secrets in docs, public data files, shell history, or issue trackers.
- Delete old identities before rotated ciphertext is verified.
- Treat age as a password manager replacement.

## Troubleshooting

### `no identity matched any of the recipients`

The local identity does not match the recipient used to encrypt the file. Restore the correct `age.txt` or re-encrypt the file for the current recipient.

### `open ~/.config/chezmoi/age.txt: no such file or directory`

Restore the identity file and permissions:

```bash
install -d -m 700 ~/.config/chezmoi
install -m 600 /path/to/age.txt ~/.config/chezmoi/age.txt
```

### Chezmoi warns that the config template changed

Regenerate the local config from the tracked template:

```bash
chezmoi init
```
