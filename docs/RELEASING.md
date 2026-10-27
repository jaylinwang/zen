# 发布

发布由 `.github/workflows/release.yml` 自动完成，无需在本机上传 DMG，也不需要个人访问令牌。

1. 更新 `Platform/macOS-Info.plist`、`Platform/iOS-Info.plist` 与 `scripts/generate-project.py` 中的版本及构建号，运行生成脚本。
2. 更新 `CHANGELOG.md`，添加 `docs/releases/vX.Y.Z.md` 发布说明。
3. 运行 `./scripts/check.sh`、`./scripts/verify-ios.sh` 和 `./scripts/package-dmg.sh`。
4. 将更改合并到 `main` 后，创建并推送与 plist 版本一致的标签：

   ```sh
   git tag -a v0.1.0 -m 'Zen 0.1.0'
   git push origin v0.1.0
   ```

标签触发完整检查和 iOS 编译，然后交叉编译 arm64 / x86_64 通用应用，临时签名、生成并挂载校验 DMG、计算 SHA-256。工作流先创建 Release 草稿，上传全部文件后才公开。工作流仅发布阶段获得 `contents: write`，PR 检查没有写权限；Actions 固定提交版本由 Dependabot 维护。

失败时查看 Actions 日志；修复后再发布新版本，不覆盖已公开的版本。尚未公开的草稿可通过重跑失败工作流恢复上传。发布成功后检查 Release 下载和校验和。

本地生成同样的安装包：

```sh
./scripts/package-dmg.sh
```

产物在 `dist/`，不加入 Git。默认应用为 universal，要求 macOS 13+。最低系统版本来自部署目标；实际运行验收范围见实现记录，不能用交叉编译代替不同设备的运行测试。

当前没有 Apple Developer ID 签名或公证。未来若接入开发者证书，应通过受保护的发布环境和 GitHub Secrets 配置，证书只导入临时 keychain，不得提交到仓库；在签名、公证及 stapling 成功前，不得宣称应用已经公证。
