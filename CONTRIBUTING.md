# 参与贡献

欢迎提交问题、文档改进和代码。交流可使用中文或英文。参与前请阅读 [行为准则](CODE_OF_CONDUCT.md)。

## 开发

需要 macOS 13+、Swift 5.9+；iOS 编译需要完整 Xcode。CI 使用 macOS 15 和 Xcode 16.4。

```sh
git clone https://github.com/jaylinwang/zen.git
cd zen
./scripts/check.sh
./scripts/build-mac.sh
open build/禅.app
```

项目没有第三方 Swift 依赖。检查程序使用独立临时目录，不读取你的个人专注记录。

## 提交更改

1. 先搜索已有 Issue。较大的功能或数据格式变更请先开 Issue 讨论。
2. Fork 仓库，从 `main` 创建描述性分支。
3. 保持改动聚焦；行为变更应提供覆盖关键场景的检查，文档更新无需添加测试。
4. 执行 `./scripts/check.sh`。涉及共享界面、资源或 iOS 配置时执行 `./scripts/verify-ios.sh`。
5. 修改 Xcode 工程配置时，先修改 `scripts/generate-project.py`，再运行它并提交生成结果。
6. 提交 PR，说明问题、改动、验证结果和已知限制；界面改动附脱敏截图。

核心检查位于 `Tests/ZenCoreTests`，应用与原生交互检查位于 `Verification/ZenChecks.swift`。它们是可执行验证程序，请使用项目脚本，而非 `swift test`。iPhone 完整模拟器流程可执行 `./scripts/check-ios-ui.sh`。

## 设计约束

- 保持离线、本地文件优先；不加入账号、分析追踪或注意力监控。
- 主动放弃不产生记录；正式记录是可读 Markdown。
- 保护草稿、外部编辑和历史格式兼容；不要静默覆盖冲突文件。
- 新素材必须记录来源、授权和处理方式；不要提交密钥、个人记录或构建产物。

提交贡献即表示你有权提供这些内容，并同意以本项目 MIT 许可证分发你的原创贡献。第三方素材保留各自授权；无需签署额外 CLA。维护者负责评审和发布，不承诺固定响应时间。

发布流程见 [RELEASING.md](docs/RELEASING.md)。
