# age 加密日常使用指南

本文记录个人日常/工作中使用 `age` 加密的常用方式。所有公钥、姓名、邮箱、仓库地址、token、密钥均使用占位符，避免把隐私信息写入文档。

## 核心概念

- `recipient`：age 公钥，可用于加密。可公开分享，但本文仍模糊化记录。
- `identity`：age 私钥，用于解密。必须保密和备份。
- 密文文件通常以 `.age` 结尾。
- 丢失 identity 后，已有密文无法恢复。

本机 chezmoi 使用的 identity 路径：

```bash
~/.config/chezmoi/age.txt
```

本文示例统一使用占位符：

```text
<AGE_PUBLIC_RECIPIENT>
```

## 安装 age CLI

chezmoi 已可使用内置 age。日常手动加密/解密时，建议安装外部 CLI：

```bash
sudo apt install age
```

## 加密单个文件

加密：

```bash
age -r <AGE_PUBLIC_RECIPIENT> -o secret.txt.age secret.txt
```

解密到文件：

```bash
age -d -i ~/.config/chezmoi/age.txt -o secret.txt secret.txt.age
```

只查看，不落盘：

```bash
age -d -i ~/.config/chezmoi/age.txt secret.txt.age
```

## 加密一段文本

适合临时保存 token、恢复码、私有配置片段。

```bash
age -r <AGE_PUBLIC_RECIPIENT> -o token.txt.age
```

粘贴内容后按 `Ctrl-D` 结束输入。

解密查看：

```bash
age -d -i ~/.config/chezmoi/age.txt token.txt.age
```

## 加密目录备份

把目录打包并直接加密，避免中间明文压缩包落盘：

```bash
tar -czf - ~/Documents/private/ \
  | age -r <AGE_PUBLIC_RECIPIENT> \
  -o private-documents.tar.gz.age
```

解密还原：

```bash
age -d -i ~/.config/chezmoi/age.txt private-documents.tar.gz.age \
  | tar -xzf -
```

## 加密给多台设备或多人

每个设备/用户都有自己的 recipient。加密时写多个 `-r`：

```bash
age \
  -r <LAPTOP_RECIPIENT> \
  -r <DESKTOP_RECIPIENT> \
  -o shared-secret.env.age \
  shared-secret.env
```

任一对应 identity 都可解密。

适合：

- 多设备同步密文
- 团队共享配置密文
- 仓库中保存加密配置

## 使用 SSH 公钥加密

age 支持 SSH public key：

```bash
age -R ~/.ssh/id_ed25519.pub -o secret.txt.age secret.txt
```

解密：

```bash
age -d -i ~/.ssh/id_ed25519 secret.txt.age
```

长期使用建议独立 age identity，不要把 SSH key 和 age identity 混为所有用途。

## 使用密码模式

适合临时分享，不适合自动化和长期管理。

加密：

```bash
age -p -o secret.txt.age secret.txt
```

解密：

```bash
age -d -o secret.txt secret.txt.age
```

## chezmoi 中使用 age

### 加密普通目标文件

例如管理私有配置文件：

```bash
chezmoi add --encrypt ~/.ssh/config.private
```

之后仓库里保存密文。应用时：

```bash
chezmoi apply
```

### 编辑已加密文件

```bash
chezmoi edit-encrypted ~/.local/share/chezmoi/home/.chezmoitemplates/private.toml.age
```

保存后仍是密文。

当前 dotfiles 中适合继续放入该密文 TOML 的内容：

- 私有 repo URL
- 真实姓名/邮箱
- 私有 API endpoint
- 机器专属 token
- 不想明文进入 Git 的模板变量

不要把 identity 私钥写入 chezmoi 仓库。

## 重新生成 chezmoi age 密钥并重新加密

核心原则：先用旧 identity 解密所有密文，再生成新 identity，更新 recipient，最后用新 recipient 重新加密。不要先覆盖旧 `age.txt`。

### 1. 备份旧 identity

```bash
old="$HOME/.config/chezmoi/age.txt"
stamp="$(date +%Y%m%d-%H%M%S)"

cp "$old" "$HOME/.config/chezmoi/age.txt.$stamp.old"
chmod 600 "$HOME/.config/chezmoi/age.txt.$stamp.old"
```

旧 identity 在新密文验证通过前不要删除。

### 2. 用旧 identity 解密现有密文

```bash
repo="$HOME/.local/share/chezmoi"
tmpdir="$(mktemp -d)"
chmod 700 "$tmpdir"

chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" > "$tmpdir/private.toml"
chmod 600 "$tmpdir/private.toml"
```

### 3. 生成新 identity 和 recipient

```bash
chezmoi age-keygen -o "$tmpdir/age.txt.new"
chmod 600 "$tmpdir/age.txt.new"

new_recipient="$(chezmoi age-keygen -y "$tmpdir/age.txt.new")"
printf '%s\n' "$new_recipient"
```

输出值就是新的 `<NEW_AGE_PUBLIC_RECIPIENT>`。

### 4. 更新 chezmoi 配置模板

编辑：

```bash
$EDITOR "$repo/home/.chezmoi.toml.tmpl"
```

把 `[age]` 中的 recipient 替换为新值：

```toml
[age]
identity = "{{ .chezmoi.homeDir }}/.config/chezmoi/age.txt"
recipient = "<NEW_AGE_PUBLIC_RECIPIENT>"
```

### 5. 替换本机 identity 并刷新 config

```bash
mv "$tmpdir/age.txt.new" "$HOME/.config/chezmoi/age.txt"
chmod 600 "$HOME/.config/chezmoi/age.txt"
chmod 700 "$HOME/.config/chezmoi"

chezmoi init
```

确认新配置生效：

```bash
chezmoi cat-config | grep -E '^(encryption|useBuiltinAge|identity|recipient) =?|^\[age\]'
```

### 6. 用新 recipient 重新加密

```bash
chezmoi encrypt < "$tmpdir/private.toml" > "$tmpdir/private.toml.age"
mv "$tmpdir/private.toml.age" "$repo/home/.chezmoitemplates/private.toml.age"
```

### 7. 验证新密文

```bash
chezmoi decrypt "$repo/home/.chezmoitemplates/private.toml.age" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/nvim.toml.tmpl" >/dev/null
chezmoi execute-template --file "$repo/home/.chezmoiexternals/zsh.toml.tmpl" >/dev/null
chezmoi diff --exclude=externals --refresh-externals=never >/dev/null
```

### 8. 清理临时明文

```bash
rm -rf "$tmpdir"
```

### 9. 提交轮换结果

```bash
git diff --check
git status --short
git add home/.chezmoi.toml.tmpl home/.chezmoitemplates/private.toml.age
git commit -m "chore: rotate chezmoi age key"
```

### 多个 `.age` 文件时

先列出所有密文：

```bash
find "$repo/home" -type f -name '*.age' -print
```

每个文件都要先用旧 key 解密，再换新 key 后重新加密：

```bash
chezmoi decrypt "$file" > "$tmpdir/$(basename "$file").plain"
chezmoi encrypt < "$tmpdir/$(basename "$file").plain" > "$file.new"
mv "$file.new" "$file"
```

## 适合使用 age 的场景

| 场景 | 示例 |
|---|---|
| dotfiles | chezmoi 私有模板变量、私有 repo URL、身份信息 |
| 开发 | `.env.age`、API token、部署密钥 |
| 备份 | 证件扫描件、合同、税务文件、恢复码 |
| 多设备同步 | 密文进 Git/云盘，identity 分设备保存 |
| 团队协作 | 给多个 teammate recipients 加密 |
| 临时分享 | `age -p` 密码模式 |
| 自动化部署 | CI 中注入 identity 解密配置 |

## 不适合使用 age 的场景

| 不适合 | 原因 |
|---|---|
| 替代密码管理器 | 缺少自动填充、分类、轮换、审计体验 |
| 频繁修改大量文件 | age 是文件加密，不是加密文件系统 |
| 共享同一个 identity | 无法区分谁解密，泄露后影响所有人 |
| 只备份密文不备份 identity | identity 丢失后密文不可恢复 |

## 推荐个人工作流

### dotfiles

- 私有模板变量：放入 `home/.chezmoitemplates/private.toml.age`
- 私有文件：用 `chezmoi add --encrypt <file>`
- 编辑密文：用 `chezmoi edit-encrypted <source-file>`

### 私人文档备份

```bash
tar -czf - ~/Documents/private/ \
  | age -r <AGE_PUBLIC_RECIPIENT> \
  -o private-backup-$(date +%F).tar.gz.age
```

### 临时保存 token

```bash
age -r <AGE_PUBLIC_RECIPIENT> -o token.age
```

粘贴 token，按 `Ctrl-D`。

### 解密但不落盘

```bash
age -d -i ~/.config/chezmoi/age.txt token.age
```

## 安全清单

必须做：

- 备份 `~/.config/chezmoi/age.txt` 到密码管理器、加密 U 盘或离线安全位置。
- 确认 `~/.config/chezmoi/age.txt` 权限为 `600`。
- 确认 `~/.config/chezmoi` 权限为 `700`。

不要做：

- 不要 commit `age.txt`。
- 不要把 identity 发给别人。
- 不要把真实 token、邮箱、私有仓库地址写入普通 Markdown。
- 不要只备份密文而不备份 identity。
- 不要把解密后的明文长期留在仓库或云盘目录。

权限检查：

```bash
stat -c '%a %n' ~/.config/chezmoi ~/.config/chezmoi/age.txt
```

期望结果：

```text
700 /home/<USER>/.config/chezmoi
600 /home/<USER>/.config/chezmoi/age.txt
```
