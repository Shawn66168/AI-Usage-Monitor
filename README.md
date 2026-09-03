# AI Usage Monitor for macOS

**AI Usage Monitor** 是一個以 Swift 6 與 SwiftUI 開發的原生 macOS 選單列應用程式，用來集中掌握 Claude、Claude Code、Codex 與 Antigravity 的剩餘用量、Token、Context 與重置時間。它也提供 Anthropic 與 OpenAI 官方組織管理 API 的選用整合，並為 ChatGPT 一般模型與 Manus 保留清楚的受限狀態，而不採用不穩定的 Cookie 擷取或網頁爬取。

> **隱私設計：** 應用程式完全在此 Mac 上處理資料；本機 provider 只讀取 quota 與 `token_count` 等數值欄位，不讀取 Prompt、回覆內容或工具內容。管理 API 金鑰只儲存在 macOS Keychain。

## 功能總覽

| 功能 | 實作狀態 | 說明 |
|---|---:|---|
| macOS 選單列 | 完成 | 常駐顯示所有已取得服務中最低的剩餘用量百分比，點擊可快速查看各服務主要 quota。 |
| 完整儀表板 | 完成 | 以側邊欄與服務卡片呈現剩餘／已用百分比、重置倒數、實際重置時間、Token、Context 與資料狀態。 |
| Claude／Claude Code | 完成 | 讀取 `~/.claude/usage-status.json` 的五小時、七天、Token、Context、模型與工作階段費用估算。 |
| Codex | 完成 | 使用 ChatGPT App 內附的官方 Codex `app-server` 讀取五小時與每週額度，並只解析本機 session 中的 `token_count` 數值事件。 |
| Antigravity | 完成 | Antigravity 執行時，透過本機 Language Server 取得模型 quota、剩餘比例與重置時間；IDE 關閉時顯示離線狀態。 |
| ChatGPT 一般模型 | 受官方限制 | 個人 ChatGPT 模型沒有穩定公開用量 API，因此顯示「官方未提供」，不擷取 Cookie。 |
| Manus | 保留正式連接器 | 顯示「等待官方資料來源」，不自動擷取帳戶點數或登入資料；正式介面需向 [Manus 說明中心](https://help.manus.im) 確認。 |
| Anthropic／OpenAI 管理 API | 完成 | 可在設定中加入 Admin Key，以 Keychain 保護，顯示近七天 Token 與本月 API 組織費用。 |
| 低用量通知 | 完成 | 剩餘用量首次低於門檻時發送 macOS 通知，同一 quota 在同一重置週期不重複提醒。 |
| 登入自動啟動 | 完成 | 使用 `SMAppService.mainApp` 註冊原生 macOS 登入項目，並顯示系統實際狀態。 |
| 自動刷新與快取 | 完成 | 預設每 60 秒更新；各 provider 失敗互不影響，並保留最近成功的非敏感快照。 |

Claude 的網頁、桌面與 Claude Code 訂閱使用相同的用量限制，Claude Code 也提供方案用量與重置資訊。[1] Codex 官方文件將 Codex 用量頁與 `/status` 列為查看 allowance 與 reset time 的正式方法。[2] Antigravity 官方 CLI `/usage` 會從後端刷新各模型 quota，而 Pro／Ultra 方案另有五小時與每週限制。[3] [4]

## 系統需求

| 項目 | 需求 |
|---|---|
| 作業系統 | macOS 14 或更新版本 |
| 處理器 | Apple Silicon（目前提供 arm64 build） |
| Claude | 若要顯示 Claude 資料，Claude Code 需曾產生 `~/.claude/usage-status.json` |
| Codex | 需安裝並登入 ChatGPT／Codex；程式會尋找 App 內附或常見路徑中的 `codex` executable |
| Antigravity | 必須正在執行，Language Server 上線後才能刷新 quota |
| 管理 API | 只有需要 API 組織彙總時才需 Admin Key；一般個人訂閱不需要也不能由這些 API 取代 |

## 安裝方式

已建置的應用程式位於：

```text
Build/AI Usage Monitor.app
```

可攜式安裝包位於：

```text
Build/AI-Usage-Monitor-macOS-arm64-v0.1.0.zip
```

先解壓縮 ZIP，將 **AI Usage Monitor.app** 拖曳到 `/Applications`，再以 Finder 開啟。此版本使用 ad-hoc 簽章，適合此 Mac 的本機測試與使用，但沒有 Apple Developer ID notarization；若 Gatekeeper 顯示提示，可對 App 按右鍵選擇「打開」，或依 macOS「隱私權與安全性」畫面核准。正式對外散布版本應改用 Developer ID 簽章與 Apple notarization。[5]

啟動後，選單列會顯示儀表圖示與最低剩餘百分比。若完整視窗未在前景，點擊選單列圖示，再選擇「儀表板」。

## 使用說明

### 儀表板

左側可切換「所有服務」或單一服務。每張服務卡片會明確分開 quota、Token 與 Context，避免將三者混為同一種限制。

| 欄位 | 定義 |
|---|---|
| 剩餘用量 | 由服務 quota 百分比換算，顯示還能使用多少。 |
| 已用用量 | 該 quota window 已消耗的比例。 |
| 重置時間 | 同時顯示相對倒數與使用者本地時區的實際日期時間。 |
| Token | 依 provider 顯示 input、output、cached input、cache write、reasoning output 與 total。 |
| Context | 顯示目前或最新 session 的已用 Token、視窗上限與比例；不同服務可取得的精確度不同。 |
| 狀態 | 「即時」代表剛取得；「快取」代表暫時無法刷新但保留最近成功資料；「官方未提供」則表示應用程式刻意不使用非正式爬取。 |

### 管理 API

在「設定 → 資料來源」勾選「顯示 API 組織用量卡片」，再加入管理金鑰。Anthropic 需要 `sk-ant-admin...` 類型的 Admin Key，一般 `sk-ant-api...` key 無權存取 Usage／Cost Admin API。OpenAI 則需要 Organization Admin Key；官方 Completions Usage API 與 Costs API 都使用此管理權限。[6] [7] [8]

應用程式不會把 Key 寫進 `.env`、JSON、UserDefaults 或 Git。輸入後直接存入 Keychain，設定畫面只顯示「已安全儲存」，不回填完整內容。建議從 1Password 複製後直接貼入設定欄位。

### 低用量通知

在「設定 → 一般」啟用系統通知並調整門檻，範圍為 5% 到 50%。macOS 第一次會詢問通知權限；若拒絕，可稍後到「系統設定 → 通知」調整。

### 登入自動啟動

在「設定 → 一般」開啟「登入後自動啟動」。若狀態顯示需要核准，前往「系統設定 → 一般 → 登入項目」允許 AI Usage Monitor。登入項目功能必須從標準 `.app` bundle 執行，直接執行裸 Mach-O binary 時不保證可註冊。

## 資料來源與隱私範圍

| Provider | 允許讀取 | 明確不讀取 |
|---|---|---|
| Claude | `usage-status.json` 的 `rate_limits`、`context_window`、`cost`、`model` 與快照時間 | `.credentials.json`、transcript、Prompt、回覆內容 |
| Codex | `account/rateLimits/read`；JSONL 中 `event_msg/token_count` 的數值欄位 | 對話文字、tool payload、登入 Token、Cookie |
| Antigravity | 本機 `GetUserStatus` 的 model label、remainingFraction、resetTime | 不把 CSRF token 寫檔、顯示或外傳 |
| API 組織 | 官方 HTTPS Usage／Cost endpoint | 不呼叫模型、不產生 Token、不修改組織設定 |
| ChatGPT／Manus | 無自動讀取 | 不解析 Session Storage、不擷取 Cookie、不爬取帳戶頁面 |

完整安全設計請閱讀 [SECURITY.md](SECURITY.md)，架構決策請閱讀 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 從原始碼建置

目前使用者的 Swift Command Line Tools 與 PackageDescription runtime 存在版本連結不一致，因此專案提供不依賴 `swift build` 的可重複建置腳本。所有 Swift 原始碼仍維持標準 Swift Package 目錄結構，安裝完整 Xcode 後可再轉為正式 Xcode project 或修復本機 toolchain 後使用 `Package.swift`。

```bash
cd "/Users/shawn/Projects/AI Useing/AIUsageMonitor"
chmod +x Scripts/build_app.sh Scripts/run_tests.sh
./Scripts/run_tests.sh
./Scripts/build_app.sh
```

`build_app.sh` 會以 Swift 6、Release 最佳化與 warnings-as-errors 編譯，建立 `Info.plist`、組裝 `.app`、執行 ad-hoc codesign 驗證，最後輸出 ZIP。

## 測試

`Scripts/run_tests.sh` 包含五組可重複單元測試、實機 provider 診斷、完整 Swift 6 警告即錯誤編譯，以及敏感路徑／硬編碼金鑰掃描。當 Antigravity 未啟動時，診斷預期回報 `unavailable`，而不是把整體刷新判定為失敗。

本機實測已確認 Claude 可取得兩個 quota window、Token 與 Context；Codex 可取得五小時與每週 quota、Token 與 Context；ChatGPT 與 Manus 正確呈現受限狀態；未設定 Admin Key 時，兩個 API 組織 provider 正確呈現 `needsConfiguration`。完整結果請見 [TEST_REPORT.md](TEST_REPORT.md)。

## 已知限制

第一版的 Antigravity quota 只在 Antigravity Language Server 執行時刷新。Codex 的七天 Token 統計只包含此 Mac 的本機 session history，不包含其他裝置或純網頁使用；Codex quota 百分比則來自官方 app-server。Claude Token／Context 依 Claude Code 提供的本機快照，並不等同整個帳戶跨裝置的完整 Token 帳本。

ChatGPT 一般模型與 Manus 個人用量維持「官方未提供」或「等待官方資料來源」是刻意的安全決策，而不是錯誤。若未來官方提供穩定且允許自動存取的介面，只需新增 conform to `UsageProvider` 的 provider，不必改寫儀表板。

## 開源參考與授權

本專案的 Antigravity 本機連接概念參考 [Antigravity-Usage-Tracker](https://github.com/timbeh/Antigravity-Usage-Tracker)，Codex app-server 與 session `token_count` 方向參考 [codex-quota-widget](https://github.com/1nuYasha-cck/codex-quota-widget)。本專案以原生 Swift 重新設計資料模型、狀態管理、介面、安全層與測試；詳細致謝請見 [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md)。

## References

[1]: https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan "Use Claude Code with your Pro or Max plan"
[2]: https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan "Using Codex with your ChatGPT plan"
[3]: https://antigravity.google/docs/cli/commands/usage/ "Antigravity Model Quotas (/usage)"
[4]: https://antigravity.google/docs/plans/ "Antigravity Plans"
[5]: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution "Notarizing macOS software before distribution"
[6]: https://www.postman.com/api-evangelist/anthropic/documentation/35240-161be0c1-64cc-4b47-91c9-725bc95b4451 "Anthropic Usage and Cost API Documentation"
[7]: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions/ "OpenAI Organization Completions Usage API"
[8]: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs/ "OpenAI Organization Costs API"
