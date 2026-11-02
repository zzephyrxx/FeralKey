# GitHub 发布准备

## 仓库信息

- **名称**：`FeralKey`
- **建议简介**：macOS 原生键盘灯光与工作流实验工具。当前实验适配 RK98（USB 258A:00C1），提供 Codex 双额度灯、分区通知、音乐律动与组合键映射，支持基于协议证据的二次开发。
- **可选英文简介**：Native macOS keyboard lighting and workflow lab. Experimental RK98 USB support, Codex quota lights, notification zones and audio-reactive RGB. Evidence-based device adaptation.
- **建议 Topics**：`macos`、`swift`、`swiftui`、`keyboard`、`rgb`、`royal-kludge`、`rk98`、`codex`、`hid`、`reverse-engineering`
- **许可证**：GPL-3.0-or-later；已有 LICENSE，不在创建仓库时另加不一致的许可证。

简介和 Topics 是供仓库 About 使用的文案，不是已经创建 GitHub 仓库的证明。不要写“全品牌适配”“无线 RGB 已支持”或“实测 60 FPS”。

## 上传源码

先在 GitHub 的目标账号创建名为 FeralKey 的空仓库；若将本项目公开开源，选择 Public。已有本地提交，不要再初始化远程 README、LICENSE 或 .gitignore。

在本地检查：

```sh
python3 scripts/check-repository.py --history
./scripts/test.sh
./scripts/test-auto-refresh.sh
./scripts/quota-smoke.sh
python3 tests/PackagingTests.py
git status --short
git diff --cached --stat
```

检查器只检查常见凭据格式与禁止路径，不能证明全部历史不存在隐私。上传前仍需审阅截图、历史提交的身份信息、设备信息和第三方资源许可。不要上传 `build/`、`evidence/`、账号文件、个人额度、未经许可的驱动/固件或原始抓包。

早期开发分支使用过 `v0.1.0`；这是分支名，不是当前应用版本（0.10.0）或已发布的版本标签。公开仓库建议使用 main。从已有历史分支首次上传时，可推送当前分支至远程 main，保留原本地分支名。仅在确认目标地址后执行以下示例，把 `OWNER` 替换为实际账号：

```sh
git remote add origin https://github.com/OWNER/FeralKey.git
git push -u origin HEAD:main
```

如果已有 origin，先核对 `git remote -v`，不要直接覆盖。只推送选定分支，**不要使用 `--mirror` 或推送本地自动工具引用**。上传后设置默认分支 main，在 About 填写简介和 Topics，检查 README 图片、Mermaid 及 Actions 结果。

## 分发与版本

当前工作目录构建是临时签名、未公证的研究预览，不能称为正式安装包。源码公开和在本机编译不要求先购买 Apple 开发者会员；面向用户提供 Developer ID 签名与公证包是后续独立发布工作。Apple 对免费开发与付费计划的区别见[开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

`scripts/package.sh` 在本地构建源码 ZIP、当前架构应用 ZIP 和 SHA-256 清单。该命令会重建默认 `build/FeralKey.app`，可能影响旧输入监控授权；测试打包建议使用 `tests/PackagingTests.py` 的隔离副本。发布前应完成真实设备验收、许可检查、签名及公证安排，并在发行说明保留支持范围和未知项。不要关闭 Gatekeeper 等系统机制作为安装步骤。

GitHub Actions 只运行离线检查、构建和打包回归，不携带账号、不访问键盘、不自动上传发行文件。首次远程执行前不能声称 CI 已通过。

首页信息顺序参考 [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements)、[Stats](https://github.com/exelban/stats)、[Hammerspoon](https://github.com/Hammerspoon/hammerspoon) 的项目介绍、安装、兼容范围和开发入口组织；未复制其代码、截图或资产。
