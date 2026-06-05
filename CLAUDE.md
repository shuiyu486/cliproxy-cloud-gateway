# cliproxy-cloud-gateway 常驻上下文

本文件是后续维护、迭代本项目的记忆模板。目标是按需路由、渐进式披露：先读最少的上下文，只在任务需要时继续展开，不要为了小改动一次性加载所有文件。

## 项目定位

cliproxy-cloud-gateway 是 CLIProxyAPI + Caddy 的轻量云端部署包。

```text
client -> Caddy HTTPS -> CLIProxyAPI -> Codex / ChatGPT 上游
```

它只负责生成和检查部署配置，不是 CLIProxyAPI 本体，不是 GUI 工具，也不是多租户计费平台。

## 先读什么

| 任务 | 先读 |
|---|---|
| 理解项目用途、用户文档、开源入口 | `README.md`、`README.en-US.md` |
| 部署步骤、Windows/Linux 服务说明 | `docs/deployment.md` |
| 修改 CLIProxyAPI 配置默认值 | `templates/cliproxy.config.template.yaml`、`tests/Test-CloudGateway.ps1` |
| 修改 Caddy 反代逻辑 | `templates/Caddyfile.template`、`docs/deployment.md` |
| 修改 Windows 生成器 | `scripts/New-CloudGateway.ps1`、`tests/Test-CloudGateway.ps1` |
| 修改 Windows 局域网一键测试 | `scripts/Start-CloudGatewayLan.ps1`、`tests/Test-CloudGateway.ps1` |
| 修改 Linux 生成器 | `scripts/new-cloud-gateway.sh`、`tests/Test-CloudGateway.ps1` |
| 修改 Linux 云端一键部署 | `scripts/install-cloud-gateway.sh`、`linux/cliproxy.service.template`、`tests/Test-CloudGateway.ps1` |
| 修改 Linux 局域网一键测试 | `scripts/start-cloud-gateway-lan.sh`、`tests/Test-CloudGateway.ps1` |
| 修改 doctor 检查 | `scripts/Test-CloudGatewayDoctor.ps1`、`scripts/test-cloud-gateway-doctor.sh` |
| 修改 Windows 开机启动方式 | `windows/Register-CLIProxyAPI-Task.ps1` |
| 修改 Linux systemd 示例 | `linux/cliproxy.service.template` |
| 发布到 GitHub 前检查 | `.gitignore`、`tests/Test-CloudGateway.ps1`、本文的 GitHub 发布检查 |

## 架构边界

- CLIProxyAPI 必须只监听本机，公网入口由 Caddy 提供。
- 这个项目主要生成部署配置和检查脚本；Linux 云端一键部署和局域网一键测试脚本可在缺少时从固定 GitHub release 来源下载 CLIProxyAPI 和 Caddy 二进制，但不得打包或提交二进制。
- 不引入 GUI、Node 构建链路、数据库、Redis、用户计费、额度管理或多租户后台。
- Windows 脚本优先兼容 Windows PowerShell 5.1。
- Linux 脚本使用 Bash；在 Windows 工作区中测试时不要依赖可执行位，文档示例用 `bash ./scripts/...`。
- GitHub 默认入口是中文 `README.md`，英文为 `README.en-US.md`。

## 不可破坏契约

- `config.yaml` 必须保留 `host: "127.0.0.1"`。
- Caddyfile 必须反代到 `127.0.0.1:<port>`。
- `remote-management.allow-remote` 必须为 `false`。
- `remote-management.secret-key` 默认必须为空字符串。
- 控制面板默认禁用：`disable-control-panel: true`。
- 生成器不得向 stdout 打印 API key。
- `client.env`、auth JSON、日志、token、私钥必须被 `.gitignore` 排除。
- 禁止提交或输出 Codex OAuth JSON、`access_token`、`refresh_token`、`id_token`、真实 API key、bearer token、原始日志。
- 生成器可以打印文件路径、目录路径、代理模式和同步文件数量。

## 配置契约

CLIProxyAPI 模板必须保留：

```yaml
codex-header-defaults:
  user-agent: 'codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0'

passthrough-headers: true
request-retry: 1
max-retry-credentials: 1
max-retry-interval: 5
```

还必须保留：

- `quota-exceeded.switch-project: true`
- `quota-exceeded.switch-preview-model: true`
- `quota-exceeded.antigravity-credits: false`
- `payload.filter` 过滤 `reasoning`、`reasoning.effort`、`thinking`
- `streaming.bootstrap-retries: 1`
- `streaming.keepalive-seconds: 15`

## 上游代理契约

`UpstreamProxyMode` 只影响：

```text
CLIProxyAPI -> Codex / ChatGPT 上游
```

规则：

- `Direct`：默认值，不写 `proxy-url`，并清理 enabled Codex auth JSON 中残留的 `proxy_url`。
- `Http`：要求提供 `UpstreamProxyUrl`，`host:port` 归一化为 `http://host:port`。
- `Socks5`：要求提供 `UpstreamProxyUrl`，`host:port` 归一化为 `socks5://host:port`。
- 不要把空 `UpstreamProxyUrl` 猜成代理。
- 不要让上游代理影响 `client -> Caddy HTTPS` 这段公网访问。

## Auth JSON 契约

生成器同步 auth metadata 时：

- 只处理 `auth/` 目录根层 `*.json`。
- 忽略 settings/test/temp 命名文件和 `codextoclaude-*` 内部状态文件。
- 只处理 `type = codex` 且 `disabled != true` 的 auth。
- 缺少 `websockets` 时补 `true`。
- 已有 `websockets: false` 必须保留。
- Direct 模式删除 `proxy_url`。
- Http/Socks5 模式写入归一化后的 `proxy_url`。
- 未知字段必须保留。

## 验证标准

修改任何脚本、模板、README 或 `CLAUDE.md` 后必跑：

```powershell
.\tests\Test-CloudGateway.ps1
```

修改 PowerShell 脚本后额外确认解析：

```powershell
$paths = @('.\scripts\New-CloudGateway.ps1', '.\scripts\Start-CloudGatewayLan.ps1', '.\scripts\Test-CloudGatewayDoctor.ps1', '.\windows\Register-CLIProxyAPI-Task.ps1', '.\tests\Test-CloudGateway.ps1')
foreach ($path in $paths) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw $errors[0].Message }
}
```

修改 Bash 脚本后额外跑 `bash -n`。

## GitHub 发布检查

发布到 `https://github.com/shuiyu486/cliproxy-cloud-gateway` 前：

- 确认 `README.md` 是中文默认入口。
- 确认 `README.en-US.md` 存在并链接回中文 README。
- 确认 README 中有 Mermaid 流程图和纯文本链路。
- 确认 `.gitignore` 排除 `generated/`、`auth/`、`logs/`、`client.env`、`*.env`、token、私钥。
- 运行测试和语法检查。
- 用 ripgrep 或等价工具扫描敏感内容：

```powershell
rg -n "(access_token|refresh_token|id_token|Bearer\s+[A-Za-z0-9._-]+|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|PRIVATE) KEY)" .
```

- 不要提交生成出来的 `config.yaml`、`Caddyfile`、`client.env`、auth JSON 或日志。

## 维护原则

- 先改测试，再改实现。
- 保持部署包小而清晰，不把 CodexToClaude 的 GUI/watchdog/自动安装逻辑搬进来。
- 用户文档面向第一次部署的人，避免只写给维护者看的内部术语。
- 如果新增功能会改变公开部署语义，README 中文和英文都要同步更新。
