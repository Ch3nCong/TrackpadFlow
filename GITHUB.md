# 将轻划源码推送到 GitHub

解压源码包，进入其中的 `TrackpadFlow` 文件夹。把项目内的文件作为仓库内容提交；ZIP 文件本身不需要放进代码仓库。

## 首次推送到空仓库

1. 登录 GitHub，创建一个空仓库，例如 `TrackpadFlow`。
2. 创建远程仓库时先不添加 README、许可证或 `.gitignore`，避免与本地首次提交冲突。
3. 在本项目根目录打开终端，将下面的 `YOUR_USERNAME` 替换成你的 GitHub 用户名；仓库名不同也需替换。

```sh
git init -b main
git add .
git commit -m "Initial import of Trackpad Flow"
git remote add origin https://github.com/YOUR_USERNAME/TrackpadFlow.git
git push -u origin main
```

推送需要使用你自己已配置的 GitHub 身份验证。若 Git 尚未设置提交者姓名和邮箱，请按 Git 的提示配置后重试提交。

## 后续更新

```sh
git status
git add .
git commit -m "Update Trackpad Flow"
git push
```

本项目的 `.gitignore` 已排除编译缓存、生成的应用、生成的图标尺寸文件、Xcode 用户状态及常见本地配置文件。应提交图标原图 `Assets/AppIcon-source-v1.png`，构建时会自动生成 `.icns` 和 `.iconset`。

也可以使用 GitHub Desktop：将解压后的项目文件夹添加为本地仓库，完成首次提交后选择 Publish repository。

## 本地验证

```sh
zsh scripts/test.sh
zsh scripts/build-app.sh
```

当前版本为 0.3.2。系统兼容性与实际硬件验证范围见 `VALIDATION.md`。
