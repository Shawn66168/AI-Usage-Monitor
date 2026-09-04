# Security and Privacy

AI Usage Monitor 採用 **local-first、read-only、data minimization** 的安全模型。應用程式的功能是呈現既有用量資料，而不是模擬使用者登入、存取對話內容或控制 AI 服務。

## 安全保證

| 控制項 | 實作 |
|---|---|
| 管理 API 金鑰 | 只存放於 macOS Keychain，使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`；不寫入 UserDefaults、快照、日誌或 Git。 |
| Claude | 只解碼 `~/.claude/usage-status.json` 中的 quota、Token、Context、模型、費用與時間欄位；不跟隨 `transcript_path`，不讀取 `.credentials.json`。 |
| Codex | 只呼叫官方本機 `account/rateLimits/read`；session JSONL 只處理包含 `token_count` 的事件並解碼數值結構。 |
| Antigravity | CSRF token 僅在記憶體中用於 loopback request；不寫檔、不顯示、不傳至非 localhost。 |
| ChatGPT／Manus | 不擷取 Cookie、不解析 Session Storage、不爬取帳戶頁面。 |
| 快取 | Application Support 只儲存正規化後的非敏感 snapshot；更新快取只含公開 Release metadata 與 ETag，不儲存原始用量回應或憑證。 |
| GitHub 更新 | 使用隔離且停用 Cookie 的 ephemeral URLSession，只呼叫固定 Public GitHub latest Release endpoint，不附帶 Authorization；Release 頁面必須通過 `https://github.com/Shawn66168/AI-Usage-Monitor/releases/` 白名單。 |
| 網路 | 設定 Admin Key 後才呼叫 Anthropic/OpenAI 官方 Usage／Cost endpoint；兩者各自具有 15 分鐘最小刷新間隔。GitHub 更新檢查只讀取公開 metadata，不傳送 AI 用量、裝置 ID 或使用者名稱。 |
| 日誌 | Provider 錯誤只顯示摘要，不輸出 request header、完整 server process command 或原始對話。 |

## 威脅模型

應用程式假設執行中的 macOS 使用者帳戶本身是可信任的，並且其他同帳戶程序已具有讀取使用者檔案的相近權限。第一版本不啟用 App Sandbox，以便唯讀存取 `~/.claude` 與 `~/.codex`；因此它不適合當作多使用者隔離邊界。若未來透過 Mac App Store 發行，應改採使用者選取資料夾與 security-scoped bookmark，或由各 CLI 主動輸出專用 snapshot。

Antigravity provider 會從本機 process list 辨識 Language Server 的 PID 與暫時 CSRF token。Token 只用於 `127.0.0.1` 的 `GetUserStatus` request；錯誤訊息與快取均不得包含它。程式不使用 shell 拼接執行未受信任內容，`Process` 的 executable 與 arguments 皆由應用程式白名單決定。

GitHub Release 的標題與說明視為未受信任的公開文字，只以 SwiftUI `Text` 顯示且限制行數，不當成 HTML、Markdown command 或 shell 執行。此版本只開啟通過 HTTPS 與 Repository path 白名單的 Release 頁面，不會自動下載、解壓或執行 Release asset。API response 上限為 1 MiB，遇到 403／429 不進行密集重試。

## 憑證操作建議

管理金鑰屬於高敏感資料。請從 1Password 複製後直接貼入應用程式設定，不要貼到聊天室、Issue、Commit、截圖或一般文字檔。Anthropic 應使用最小必要權限的 Admin Key；OpenAI 應使用 Organization Admin Key。若懷疑洩漏，應立即在供應商控制台撤銷並重新建立。

一般背景或手動「更新用量」不會繞過 Admin API 的 15 分鐘限制；只有使用者新增或移除對應 Keychain 憑證時，才會對該 Provider 強制刷新一次，以立即反映設定狀態。App 啟動時若已有快取，會以快照時間延續限制，避免每次重開 App 都重新呼叫管理 API。

## 驗證

`Scripts/run_tests.sh` 會驗證 15 分鐘 Provider 刷新閘門、強制刷新例外與本機 Provider 不受限行為，並執行硬編碼 Secret pattern 掃描、Git 完整歷史掃描、敏感檔名掃描、個人絕對路徑掃描，以及對 `.credentials.json`、Session Storage、transcript、history 與對話 payload 讀取模式的禁止項目掃描。`Scripts/publish_github_release.sh` 在任何 GitHub 推送前還會解壓本次 App／Source ZIP，重新掃描 Secret、憑證檔、Cookie、個人路徑與 binary build path；任一項失敗便中止。這些自動檢查不能取代第三方專業安全稽核，但可阻擋常見洩漏與回歸。

## 回報安全問題

請不要在公開 Issue 貼上帳戶識別資訊、API Key、Cookie、CSRF token、完整 session JSONL 或 Claude transcript。回報時只需提供應用程式版本、macOS 版本、provider 名稱、狀態碼與已移除敏感資料的錯誤摘要。
