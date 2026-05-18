# age 加密指南

语言：[English](AGE_ENCRYPTION_GUIDE.md) | 中文

本仓库通过 chezmoi 使用 `age` 加密，把私有 dotfiles 数据安全地保存到 Git 中，同时避免明文提交敏感信息。

设计保持简洁：

- 公开默认值保留在 `.chezmoidata/`。
- 私有模板数据集中放入一个加密 TOML 文件。
- age identity 私钥只保存在本机，不进入仓库。
- 日常加密、解密和 apply 流程交给 chezmoi 处理。

## 仓库布局

```text
home/.chezmoi.toml.tmpl                 chezmoi 配置模板
home/.chezmoidata/                      公开默认值和功能开关
home/.chezmoitemplates/private.toml.age 加密的私有模板数据
home/.chezmoiexternals/                 使用私有数据的模板
home/.chezmoiignore                     排除本机私密文件
```

当前加密私有数据主要用于：

- Git 身份信息
- 私有仓库 URL
- 私有模板变量

不要把 token、私钥、账号 ID、私有仓库 URL 写入 Markdown、明文 TOML、shell history 或命令参数。

## 核心概念

| 名称 | 含义 | 可以提交？ |
|---|---|---|
| recipient | age 公钥，用于加密 | 可以 |
| identity | age 私钥，用于解密 | 不可以 |
| ciphertext | `.age` 密文文件 | 可以 |
| plaintext | 解密后的明文 | 不可以 |

本机 identity 路径：

```text
~/.config/chezmoi/age.txt
```

如果丢失这个文件，已有密文无法恢复。必须在仓库之外备份。

## chezmoi 配置

仓库中的配置模板启用 age：

```toml
encryption = "age"
useBuiltinAge = true

[age]
identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/age.txt"
recipient = "<AGE_PUBLIC_RECIPIENT>"
```

`useBuiltinAge = true` 让 chezmoi 在没有外部 `age` CLI 时也能工作。外部 CLI 仍适合在 chezmoi 之外临时加密文件。

## 新机器初始化

1. 安装 `chezmoi` 和 `git`。
2. clone 或 init 本 dotfiles 仓库。
3. 从密码管理器或离线备份恢复 age identity。
4. apply dotfiles。

```bash
chezmoi init <repo>
install -d -m 700 ~/.config/chezmoi
install -m 600 /path/to/age.txt ~/.config/chezmoi/age.txt
chezmoi apply
```

检查权限：

```bash
stat -c '%a %n' ~/.config/chezmoi ~/.config/chezmoi/age.txt
```

期望形态：

```text
700 /home/<USER>/.config/chezmoi
600 /home/<USER>/.config/chezmoi/age.txt
```

## 日常操作

### 验证加密数据但不打印内容

```bash
chezmoi decrypt ~/.local/share/chezmoi/home/.chezmoitemplates/private.toml.age >/dev/null
```

### 渲染依赖私有数据的模板

```bash
repo="$HOME/.local/share/chezmoi"

chezmoi execute-template --file "$repo/home/.chezmoiexternals/nvim.toml.tmpl" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/zsh.toml.tmpl" >/dev/null
```

### 预览 dotfiles 变更

不需要查看外部仓库 URL 时，避免把私有 URL 打印出来：

```bash
chezmoi diff --exclude=externals --refresh-externals=never
```

### 编辑加密私有模板数据

```bash
chezmoi edit-encrypted ~/.local/share/chezmoi/home/.chezmoitemplates/private.toml.age
```

这个文件只放模板变量。更大的 secret 文件应使用独立加密目标文件。

## 添加加密目标文件

如果某个私有文件需要在 `chezmoi apply` 后出现在 home 目录中，使用 chezmoi 的加密 source-state：

```bash
chezmoi add --encrypt ~/.ssh/config.private
chezmoi add --encrypt ~/.config/example/credentials.toml
```

chezmoi 会在 source tree 中保存密文，并在 apply 时解密。

适合：

- 私有 SSH 配置片段
- API credential 文件
- 应用专属 secret 配置

不适合：

- age identity 本身
- 更适合密码管理器保存的 secret
- 高频修改的大量数据

## 手动使用 age

chezmoi 可以使用内置 age；如果需要在 dotfiles 之外加密文件，可以安装外部 CLI。

Debian/Ubuntu：

```bash
sudo apt install age
```

加密文件：

```bash
age -r <AGE_PUBLIC_RECIPIENT> -o secret.txt.age secret.txt
```

解密到 stdout：

```bash
age -d -i ~/.config/chezmoi/age.txt secret.txt.age
```

不落盘明文压缩包，直接加密目录备份：

```bash
tar -czf - ~/Documents/private/ \
  | age -r <AGE_PUBLIC_RECIPIENT> \
  -o private-documents.tar.gz.age
```

恢复：

```bash
age -d -i ~/.config/chezmoi/age.txt private-documents.tar.gz.age \
  | tar -xzf -
```

## 密钥轮换

只在必要时轮换：identity 暴露、设备退役、清理 recipient，或计划迁移。

原则：先用旧 identity 解密，再用新 recipient 加密。新密文验证通过前，不要覆盖或删除旧 identity。

### 1. 准备私有工作目录

```bash
repo="$HOME/.local/share/chezmoi"
tmpdir="$(mktemp -d)"
chmod 700 "$tmpdir"
```

### 2. 保留旧 identity

```bash
cp ~/.config/chezmoi/age.txt "$tmpdir/age.txt.old"
chmod 600 "$tmpdir/age.txt.old"
```

### 3. 解密当前私有数据

```bash
chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" > "$tmpdir/private.toml"
chmod 600 "$tmpdir/private.toml"
```

### 4. 生成新 identity 和 recipient

```bash
chezmoi age-keygen -o "$tmpdir/age.txt.new"
chmod 600 "$tmpdir/age.txt.new"

new_recipient="$(chezmoi age-keygen -y "$tmpdir/age.txt.new")"
printf '%s\n' "$new_recipient"
```

### 5. 更新 chezmoi 配置

编辑 `home/.chezmoi.toml.tmpl`，替换 recipient：

```toml
[age]
identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/age.txt"
recipient = "<NEW_AGE_PUBLIC_RECIPIENT>"
```

安装新 identity 并重新生成本机配置：

```bash
install -m 600 "$tmpdir/age.txt.new" ~/.config/chezmoi/age.txt
chezmoi init
```

### 6. 重新加密私有数据

```bash
chezmoi encrypt < "$tmpdir/private.toml" > "$tmpdir/private.toml.age"
mv "$tmpdir/private.toml.age" "$repo/home/.chezmoitemplates/private.toml.age"
```

如果还有其他 `.age` 文件，需要先用旧 identity 逐个解密，切换新 key 后再逐个重新加密。

### 7. 验证

```bash
chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/nvim.toml.tmpl" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/zsh.toml.tmpl" >/dev/null
chezmoi diff --exclude=externals --refresh-externals=never >/dev/null
git diff --check
```

验证通过后再清理：

```bash
rm -rf "$tmpdir"
```

## 安全清单

应该做：

- 把 `~/.config/chezmoi/age.txt` 备份到密码管理器或离线加密存储。
- 保持 `~/.config/chezmoi` 权限为 `700`。
- 保持 `~/.config/chezmoi/age.txt` 权限为 `600`。
- 只提交密文和 public recipient。
- 提交加密流程相关变更前先 review diff。

不要做：

- 不要提交 `age.txt` 或解密后的 private TOML。
- 不要共享 age identity。
- 不要把真实 secret 写入文档、公开数据文件、shell history 或 issue tracker。
- 不要在新密文验证前删除旧 identity。
- 不要把 age 当作密码管理器的完整替代品。

## 故障处理

### `no identity matched any of the recipients`

本机 identity 与密文 recipient 不匹配。恢复正确的 `age.txt`，或用当前 recipient 重新加密该文件。

### `open ~/.config/chezmoi/age.txt: no such file or directory`

恢复 identity 文件和权限：

```bash
install -d -m 700 ~/.config/chezmoi
install -m 600 /path/to/age.txt ~/.config/chezmoi/age.txt
```

### chezmoi 提示 config template 已变化

从仓库模板重新生成本机配置：

```bash
chezmoi init
```
