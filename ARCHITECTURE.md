# AI Usage Monitor：架構與安全設計

**作者：Manus AI**  
**目標平台：macOS 14 或更新版本，Apple Silicon**  
**技術：Swift 6、SwiftUI、AppKit、ServiceManagement、UserNotifications、Security.framework**

## 1. 產品定位

AI Usage Monitor 是一個完全在使用者 Mac 上執行的原生應用程式。它以選單列常駐工具與完整儀表板呈現 Claude、Claude Code、Codex、Antigravity、ChatGPT 與 Manus 的用量狀態；所有本機連接器皆採唯讀方式，不讀取對話內容、不擷取瀏覽器 Cookie，也不將用量資料傳送到第三方伺服器。

> **核心安全原則：** 本機連接器只處理官方客戶端已產生的 quota、Token、Context 與重置欄位；管理 API 憑證只存放於 macOS Keychain，不寫入設定檔、日誌或 Git。

## 2. 資料來源與能力矩陣

| 服務 | 主要資料來源 | 即時配額與重置 | Token | Context | 離線／受限狀態 |
|---|---|---:|---:|---:|---|
| Claude／Claude Code | `~/.claude/usage-status.json` | 五小時與七天視窗 | Input、Output、Cache、總量 | 已用比例、上限 | Claude Code 尚未產生快照時顯示等待資料；快照過期時顯示資料時間 |
| Codex | ChatGPT App 內附 Codex `app-server` 的 `account/rateLimits/read` | 五小時與每週視窗 | 只解析 session JSONL 的 `token_count` 事件 | 最新 session 的 `model_context_window` | Codex 未登入或 app-server 無法啟動時保留最近成功快照 |
| Antigravity | 執行中的本機 Language Server `GetUserStatus` | 各模型／quota bucket 的剩餘比例與重置時間 | 官方本機 quota 回應若未提供則標示未提供 | 官方本機 quota 回應若未提供則標示未提供 | IDE 關閉時顯示「需啟動 Antigravity」並保留最近快照 |
| ChatGPT 一般模型 | 官方未提供穩定個人用量 API | 不自動擷取 | 不自動擷取 | 不自動擷取 | 顯示「官方未提供」；不採用 Cookie 或網頁爬取 |
| Manus | 保留正式連接器介面 | 待官方正式介面 | 待官方正式介面 | 待官方正式介面 | 顯示「等待官方資料來源」；不進行帳戶點數爬取 |
| Anthropic API 組織 | 可選官方 Admin Usage／Cost API | 組織級 API 用量 | 可按時間與模型彙總 | 不代表 Claude 個人訂閱 Context | Keychain 未設定 Admin Key 時停用 |
| OpenAI API 組織 | 可選官方 Organization Usage API | 組織級 API 用量 | 可按時間與模型彙總 | 不代表 ChatGPT 個人訂閱 Context | Keychain 未設定 Admin Key 時停用 |

Claude 的網頁、桌面與 Claude Code 訂閱用量共用限制；Claude Code 官方介面能顯示方案使用量與重置資訊。[1] Codex 官方說明則將 Codex 用量頁與互動式 `/status` 列為查看剩餘額度及重置時間的正式方法。[2] Antigravity 官方 CLI `/usage` 會刷新並顯示各模型 quota；Pro／Ultra 另有五小時與每週限制。[3] [4]

## 3. 應用程式分層

| 層級 | 元件 | 責任 |
|---|---|---|
| Presentation | `DashboardView`、`MenuBarView`、`SettingsView` | 顯示總覽、服務卡片、quota 進度、Token／Context、資料品質與設定 |
| State | `UsageStore` | 平行刷新各 provider、合併快照、管理 loading/error/stale、通知判斷與本機快取 |
| Domain | `AIServiceSnapshot`、`QuotaWindow`、`TokenUsage`、`ContextUsage` | 提供跨服務一致資料模型，明確區分 used 與 remaining |
| Providers | `ClaudeProvider`、`CodexProvider`、`AntigravityProvider`、`UnsupportedProvider` | 封裝各官方客戶端或 API 的資料差異，統一輸出 snapshot |
| Infrastructure | `ProcessRunner`、`SnapshotCache`、`KeychainStore`、`LaunchAtLoginManager`、`NotificationManager` | 執行白名單本機命令、持久化非敏感資料、保護 API Key、登入啟動與系統通知 |

Provider 介面採 `async throws`，每個 provider 的失敗彼此隔離。`UsageStore` 每 60 秒刷新一次本機來源，每 5 分鐘刷新需要網路或 app-server 的來源；使用者也可手動刷新。連續錯誤採漸進退避，避免高頻輪詢。

## 4. 核心資料模型

```swift
struct AIServiceSnapshot: Identifiable, Codable, Sendable {
    let id: ServiceKind
    var displayName: String
    var planName: String?
    var quotas: [QuotaWindow]
    var tokenUsage: TokenUsage?
    var contextUsage: ContextUsage?
    var status: ProviderStatus
    var sourceDescription: String
    var fetchedAt: Date
}

struct QuotaWindow: Identifiable, Codable, Sendable {
    var id: String
    var label: String
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var scope: QuotaScope
}
```

百分比在 domain 層統一限制於 `0...100`。所有 reset timestamp 轉換成 `Date`，畫面依使用者時區顯示「剩餘多久」與「實際重置日期時間」。Token 不同廠商的 cache 與 reasoning 欄位不完全相同，因此保留分項並另外計算 total；不把 Token 數量誤當作訂閱 quota 百分比。

## 5. 本機檔案與隱私範圍

應用程式不啟用 App Sandbox，讓個人版工具可以唯讀存取 `~/.claude` 與 `~/.codex`；發行版仍採 Hardened Runtime 相容設計。Provider 只讀取以下白名單內容：

| 路徑／來源 | 允許讀取 | 明確禁止 |
|---|---|---|
| `~/.claude/usage-status.json` | `rate_limits`、`context_window`、`cost`、`model`、快照時間 | `transcript_path` 指向的對話內容、credentials |
| `~/.codex/sessions/**/*.jsonl` | `type == event_msg` 且 `payload.type == token_count` 的數值欄位 | prompt、response、tool payload、對話文字 |
| Codex app-server | `account/rateLimits/read` 回應 | 帳戶 Token、Cookie、其他非用量 API |
| Antigravity 本機伺服器 | `GetUserStatus` 的 model label、remainingFraction、resetTime | 將 CSRF token 寫檔、記錄或傳出本機 |
| Application Support | 正規化後的最近快照與非敏感偏好 | API Key、Cookie、原始 session 內容 |

## 6. 管理 API 與 Keychain

設定頁提供 Anthropic Admin Key 與 OpenAI Admin Key 的可選欄位。新增或更新時直接寫入 Keychain；畫面只顯示是否已設定，不回填完整金鑰。網路請求使用 `URLSession`、HTTPS、合理 timeout 與最小權限端點。管理 API 只補充 API 組織用量，畫面會清楚標示「API 組織」以避免與個人 Claude／ChatGPT 訂閱額度混淆。

建議使用者從 1Password 取得憑證後直接貼入 Keychain 設定欄位，且不要將任何金鑰寫入專案 `.env`、原始碼或 Git 歷史。

## 7. 選單列、通知與登入啟動

選單列預設顯示所有已取得服務中最低的剩餘百分比；點擊後顯示每個服務的主要 quota、最近更新時間、刷新與開啟儀表板按鈕。當任一 quota 從高於門檻下降到低於門檻時，透過 `UNUserNotificationCenter` 發送一次通知；同一 quota 在重置前不重複轟炸。預設警示門檻為 20%，可在設定頁調整。

登入自動啟動使用 `SMAppService.mainApp`。開關狀態與系統實際註冊狀態同步；若應用程式仍在開發資料夾或系統拒絕註冊，介面顯示可理解的錯誤，不宣稱已成功。

## 8. 建置與發行策略

目前 Mac 僅有 Swift Command Line Tools，第一版使用 Swift Package Manager 建置 executable，腳本再組裝標準 `.app` bundle、產生 `Info.plist` 並進行 ad-hoc codesign。此版本可供本機測試與使用。若要無 Gatekeeper 警告地散布給其他 Mac，需安裝完整 Xcode，使用 Apple Developer ID 簽章並完成 notarization。

## 9. 測試策略

| 類型 | 驗證內容 |
|---|---|
| Parser 單元測試 | Claude JSON、Codex JSON-RPC、Codex token_count、Antigravity quota 回應、日期與百分比邊界 |
| 安全測試 | 確認不讀取 prompt/response、log 不出現 CSRF/API key、快取不含 credentials |
| Provider 容錯 | 檔案不存在、JSON 截斷、IDE 關閉、CLI 未登入、網路 timeout、API 401/429 |
| UI 狀態 | loading、正常、stale、部分可用、未支援、低用量、重置後恢復 |
| 實機整合 | Claude 現有快照、Codex app-server 與 session JSONL、Antigravity 啟動後 loopback 讀取 |
| 發行驗證 | `swift test`、Release build、`.app` bundle、codesign 驗證、啟動與登入項目狀態 |

## References

[1]: https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan "Use Claude Code with your Pro or Max plan"
[2]: https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan "Using Codex with your ChatGPT plan"
[3]: https://antigravity.google/docs/cli/commands/usage/ "Antigravity Model Quotas (/usage)"
[4]: https://antigravity.google/docs/plans/ "Antigravity Plans"
