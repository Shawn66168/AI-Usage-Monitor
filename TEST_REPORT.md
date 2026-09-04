# AI Usage Monitor 測試報告

**測試日期：2026-09-04**  
**平台：macOS 26.6.2、Apple Silicon arm64、Swift 6.3.3**  
**版本：0.2.0**

## 結論

核心功能、GitHub 更新提示、資料解析、安全控制與 Release 打包均已通過自動化驗證。Claude 與 Codex 已以此 Mac 的真實本機資料完成整合測試；Antigravity 在未啟動時正確回報 `unavailable`；ChatGPT 與 Manus 正確維持受限狀態；未設定管理金鑰時，Anthropic API 與 OpenAI API 正確回報 `needsConfiguration`。

> **整體結果：PASS。** 0.2.0 Release `.app` 已由 macOS Launch Services 啟動，版本、bundle identifier、arm64 binary、Info.plist、ad-hoc codesign、App／Source ZIP、SHA-256 與敏感資訊掃描均通過驗證。

## 自動化測試

| 測試 | 結果 | 驗證內容 |
|---|---:|---|
| 核心單元測試 | PASS（5 組） | Quota 正規化、日期解析、Claude Fixture、ProcessRunner、Keychain round trip。 |
| 更新檢查測試 | PASS（7 組） | SemVer、GitHub payload、版本提示、忽略版本、ETag、Prerelease、cache 與 request security。 |
| Swift 6 Release 編譯 | PASS | `-warnings-as-errors`、whole-module optimization，無 warning 或 error。 |
| 隱私禁止項掃描 | PASS | 未發現 `.credentials.json`、Session Storage、transcript、history 或對話 payload 讀取。 |
| 目前原始碼 Secret 掃描 | PASS | 未發現 API Key、GitHub Token、私鑰或 Authorization value。 |
| Git 完整歷史 Secret 掃描 | PASS | 所有 Commit 未發現金鑰或 Token pattern。 |
| 敏感檔名掃描 | PASS | 未追蹤 `.env`、credentials、Cookie、PEM、P8、P12、SSH key 或 provisioning profile。 |
| 個人絕對路徑掃描 | PASS | 目前可發布原始碼未包含 `/Users/...` 或 `/home/...`。 |

## GitHub 更新檢查驗證

| 情境 | 結果 |
|---|---:|
| `v` 前綴與 `X.Y.Z` 正規化 | PASS |
| major／minor／patch 與 prerelease 比較 | PASS |
| 遠端版本高於本機時提示 | PASS |
| 相同版本不提示 | PASS |
| Prerelease 不提示正式版使用者 | PASS |
| 忽略與重新提示指定版本 | PASS |
| ETag conditional request 與 304 cache | PASS |
| Request 不含 Authorization | PASS |
| Request 不含 Cookie | PASS |
| Endpoint 固定為 GitHub latest Release | PASS |
| Release URL 強制 HTTPS 與 Repository path 白名單 | PASS |
| 快取不含憑證、Cookie 或 CSRF Token | PASS |

Repository 在功能開發與資安稽核階段仍保持 Private，因此未驗證請求的即時 GitHub API 測試會在切換 Public 後執行；公開前不以 Token 規避此限制。

## 實機 Provider 診斷

| Provider | 狀態 | Quota | Token | Context | 判定 |
|---|---|---:|---:|---:|---|
| Claude／Claude Code | `available` | 2 | 有 | 有 | 已成功讀取此 Mac 的 Claude Code 快照。 |
| Codex | `available` | 2 | 有 | 有 | 已成功讀取官方 app-server 的五小時／每週限制與本機 session。 |
| Antigravity | `unavailable` | 0 | 無 | 無 | 測試時 IDE 未啟動；符合設計，不影響其他 provider。 |
| ChatGPT | `unsupported` | 0 | 無 | 無 | 正確顯示官方未提供個人模型用量 API。 |
| Manus | `unsupported` | 0 | 無 | 無 | 正確顯示等待官方正式資料來源。 |
| Anthropic API | `needsConfiguration` | 0 | 無 | 無 | 未設定 Admin Key 時狀態正確。 |
| OpenAI API | `needsConfiguration` | 0 | 無 | 無 | 未設定 Organization Admin Key 時狀態正確。 |

## Release Bundle 與資產驗證

| 項目 | 結果 |
|---|---:|
| Bundle identifier `com.xing.ai-usage-monitor` | PASS |
| `CFBundleShortVersionString` 為 `0.2.0` | PASS |
| Mach-O arm64 | PASS |
| Info.plist lint | PASS |
| ad-hoc codesign `--deep --strict` | PASS |
| Launch Services 啟動與程序存活 | PASS |
| App ZIP SHA-256 | PASS |
| Source ZIP SHA-256 | PASS |
| App／Source ZIP Secret 掃描 | PASS |
| App／Source ZIP 敏感檔名掃描 | PASS |
| Source ZIP 個人絕對路徑掃描 | PASS |
| Compiled binary build path 掃描 | PASS |

輸出檔案：

```text
Build/AI Usage Monitor.app
Build/AI-Usage-Monitor-macOS-arm64-v0.2.0.zip
Build/AI-Usage-Monitor-Source-v0.2.0.zip
Build/SHA256SUMS-v0.2.0.txt
```

## 視覺驗證限制

遠端命令工作階段沒有 macOS WindowServer 螢幕擷取權限，因此無法擷取選單列 `NEW` 徽章影像。SwiftUI 選單列、更新卡片與設定頁已通過完整 Release 編譯，App bundle 亦成功啟動；安裝後仍建議人工確認目前顯示器縮放下的選單列寬度與 Release Notes 摘要排版。

## 執行方式

```bash
cd "/path/to/AIUsageMonitor"
./Scripts/run_tests.sh
VERSION=0.2.0 BUILD_NUMBER=5 ./Scripts/build_app.sh
./Scripts/security_audit.sh --artifacts Build
```

## GitHub Releases 發布防呆

發布腳本會強制要求 `--repo` 與合法 SemVer，拒絕髒工作目錄、舊版 Release Notes、衝突 Tag 與既有 Release。它會在任何 Push 前執行完整測試、建立本次版本的 App／Source ZIP、產生 SHA-256，並只將本次兩個 ZIP 放入隔離目錄執行資產安全稽核，避免舊版 Build artifact 干擾判定。
