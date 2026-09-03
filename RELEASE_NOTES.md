# AI Usage Monitor 0.1.0

這是原生 macOS AI 用量監控應用程式的第一個可執行版本。此版本已完成 SwiftUI 選單列、完整儀表板、Claude／Claude Code、Codex、Antigravity、本機 Token 與 Context、低用量通知、登入自動啟動、Keychain 及 Anthropic／OpenAI 管理 API 架構。

## 可用整合

| 服務 | 0.1.0 狀態 |
|---|---|
| Claude／Claude Code | 可即時顯示五小時、七天、Token、Context、模型與重置時間。 |
| Codex | 可顯示五小時、每週、Token、最新 session Context 與重置時間。 |
| Antigravity | IDE 執行時可顯示各模型或共享 bucket 的 quota 與重置時間。 |
| ChatGPT 一般模型 | 顯示「官方未提供」，不使用 Cookie 爬取。 |
| Manus | 顯示「等待官方資料來源」，不擷取帳戶點數。 |
| Anthropic API | 可選 Admin Key，顯示近七天 Token 與本月 API 組織費用。 |
| OpenAI API | 可選 Organization Admin Key，顯示近七天 Token 與本月 API 組織費用。 |

## 安裝

解壓縮 `AI-Usage-Monitor-macOS-arm64-v0.1.0.zip`，將 **AI Usage Monitor.app** 移到 `/Applications` 後開啟。此版本為 ad-hoc 簽章，適合本機使用；首次啟動若出現 Gatekeeper 提示，請以 Finder 右鍵選擇「打開」。

## 驗證狀態

Release build 已通過 Swift 6 warnings-as-errors、五組單元測試、實機 provider 診斷、Keychain round trip、敏感路徑掃描、硬編碼 secret 掃描、Info.plist lint、codesign verify 與 Launch Services 啟動測試。

## 已知限制

Codex 的七天 Token 統計只包含此 Mac 的本機 session history。Antigravity 需保持 IDE 執行才能刷新。ChatGPT 一般模型與 Manus 在官方提供穩定、允許自動存取的個人用量介面前，不會自動讀取。
