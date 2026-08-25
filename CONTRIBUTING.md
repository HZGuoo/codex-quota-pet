# Contributing to Codex Quota Pet

感谢你愿意改进 Codex Quota Pet。项目欢迎错误修复、兼容性改进、测试、文档和界面优化。

## 开始之前

- 对较大的功能或协议调整，请先创建 Issue，说明使用场景和兼容性影响。
- 不要在 Issue、日志或测试数据中提交访问令牌、账号信息、代理凭据或私人会话内容。
- 变更应继续支持 macOS 13、Apple Silicon 和 Intel Mac。
- 不要引入第三方运行时依赖，除非 Issue 中已经讨论并说明必要性。

## 本地开发

需要 Swift 6 和 macOS 13 或更新版本。克隆仓库后运行：

```bash
Scripts/build-app.sh
open "dist/Codex Quota Pet.app"
```

执行自测：

```bash
swift run --disable-sandbox CodexQuotaPetSelfTests
```

如果本机 Swift 编译器与默认 SDK 不匹配，可以将 `CODEX_QUOTA_SDKROOT` 指向兼容的 macOS SDK：

```bash
CODEX_QUOTA_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" Scripts/build-app.sh
```

## Pull Request 要求

- PR 只解决一个清晰的问题，并说明用户可见变化。
- 新协议解析或状态逻辑必须包含回归测试。
- 界面调整请附修改前后的截图，并检查浅色、深色及多显示器场景。
- 不得记录或复制 Codex/ChatGPT 认证令牌。
- 提交前请运行自测、Universal 2 Release 构建和 `codesign --verify --deep --strict`。

提交贡献即表示你有权提供相关代码，并同意项目按照仓库许可证分发该贡献。
