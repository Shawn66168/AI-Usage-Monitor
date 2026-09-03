# AI Usage Monitor 測試報告

**測試日期：2026-09-04**  
**平台：macOS 26.6.2、Apple Silicon arm64、Swift 6.3.3**  
**版本：0.1.0**

## 結論

核心功能、資料解析、安全控制與 Release 打包均已通過自動化驗證。Claude 與 Codex 已以使用者此 Mac 的真實本機資料完成整合測試；Antigravity 在未啟動時正確回報 `unavailable`；ChatGPT 與 Manus 正確維持受限狀態；未設定管理金鑰時，Anthropic API 與 OpenAI API 正確回報 `needsConfiguration`。

> **整體結果：PASS。** Release `.app` 已成功由 macOS Launch Services 啟動並維持執行，bundle identifier、arm64 binary、Info.plist 與 ad-hoc codesign 均通過驗證。

## 自動化測試

| 測試 | 結果 | 驗證內容 |
|---|---:|---|
| Quota 正規化 | PASS | `usedPercent` 與 `remainingPercent` 限制於 0–100，兩者合計為 100。 |
| 日期解析 | PASS | 支援有／無 fractional seconds 的 ISO 8601 reset time。 |
| Claude Fixture | PASS | 五小時、七天、Token、Context、重置時間與 session cost 解析。 |
| ProcessRunner | PASS | stdout 完整讀取、exit code、timeout 架構；修正大量 `ps` 輸出造成 Pipe 填滿的風險。 |
| Keychain Round Trip | PASS | 在隔離的測試 service 中完成寫入、讀回與刪除，測試資料不殘留。 |
| Swift 6 Release 編譯 | PASS | `-warnings-as-errors`、whole-module optimization，無 warning 或 error。 |
| 隱私禁止項掃描 | PASS | 未發現 `.credentials.json`、Session Storage、transcript、history 或對話 payload 讀取。 |
| Secret pattern 掃描 | PASS | 原始碼與文件未發現硬編碼 Anthropic、OpenAI 或 Google key。 |

## 實機 Provider 診斷

實機全量 provider 刷新耗時約 **0.79 秒**。診斷報告如下：

| Provider | 狀態 | Quota | Token | Context | 判定 |
|---|---|---:|---:|---:|---|
| Claude／Claude Code | `available` | 2 | 有 | 有 | 已成功讀取此 Mac 的 Claude Code 快照。 |
| Codex | `available` | 2 | 有 | 有 | 已成功讀取官方 app-server 的五小時／每週限制與本機 session。 |
| Antigravity | `unavailable` | 0 | 無 | 無 | 測試時 IDE 未啟動；符合設計，不影響其他 provider。 |
| ChatGPT | `unsupported` | 0 | 無 | 無 | 正確顯示官方未提供個人模型用量 API。 |
| Manus | `unsupported` | 0 | 無 | 無 | 正確顯示等待官方正式資料來源。 |
| Anthropic API | `needsConfiguration` | 0 | 無 | 無 | 未設定 Admin Key 時狀態正確。 |
| OpenAI API | `needsConfiguration` | 0 | 無 | 無 | 未設定 Organization Admin Key 時狀態正確。 |

## Release Bundle 驗證

| 項目 | 結果 |
|---|---:|
| Bundle identifier `com.xing.ai-usage-monitor` | PASS |
| Mach-O arm64 | PASS |
| Info.plist lint | PASS |
| ad-hoc codesign verify `--deep --strict` | PASS |
| ZIP 建立 | PASS |
| Launch Services 註冊與啟動 | PASS |
| 啟動後程序穩定存在 | PASS |

輸出檔案：

```text
Build/AI Usage Monitor.app
Build/AI-Usage-Monitor-macOS-arm64-v0.1.0.zip
```

## 視覺驗證限制

遠端命令工作階段沒有 macOS WindowServer 螢幕擷取權限，因此 `screencapture` 無法取得儀表板影像；這不影響 Release App 的啟動與功能診斷。SwiftUI 視圖已通過完整 Release 編譯，App bundle 亦已由 Launch Services 成功啟動。首次由 Finder 開啟後，仍建議使用者人工確認選單列寬度、視窗大小與目前顯示器縮放下的排版，若需要可再進行第二輪視覺微調。

## 執行方式

```bash
cd "/Users/shawn/Projects/AI Useing/AIUsageMonitor"
./Scripts/run_tests.sh
./Scripts/build_app.sh
```
