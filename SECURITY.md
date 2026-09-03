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
| 快取 | Application Support 只儲存正規化後的非敏感 snapshot，不儲存原始回應或憑證。 |
| 網路 | 只有使用者設定 Admin Key 後，才呼叫 Anthropic 或 OpenAI 官方 HTTPS Usage／Cost endpoint。 |
| 日誌 | Provider 錯誤只顯示摘要，不輸出 request header、完整 server process command 或原始對話。 |

## 威脅模型

應用程式假設執行中的 macOS 使用者帳戶本身是可信任的，並且其他同帳戶程序已具有讀取使用者檔案的相近權限。第一版本不啟用 App Sandbox，以便唯讀存取 `~/.claude` 與 `~/.codex`；因此它不適合當作多使用者隔離邊界。若未來透過 Mac App Store 發行，應改採使用者選取資料夾與 security-scoped bookmark，或由各 CLI 主動輸出專用 snapshot。

Antigravity provider 會從本機 process list 辨識 Language Server 的 PID 與暫時 CSRF token。Token 只用於 `127.0.0.1` 的 `GetUserStatus` request；錯誤訊息與快取均不得包含它。程式不使用 shell 拼接執行未受信任內容，`Process` 的 executable 與 arguments 皆由應用程式白名單決定。

## 憑證操作建議

管理金鑰屬於高敏感資料。請從 1Password 複製後直接貼入應用程式設定，不要貼到聊天室、Issue、Commit、截圖或一般文字檔。Anthropic 應使用最小必要權限的 Admin Key；OpenAI 應使用 Organization Admin Key。若懷疑洩漏，應立即在供應商控制台撤銷並重新建立。

## 驗證

`Scripts/run_tests.sh` 會執行硬編碼 Secret pattern 掃描，以及對 `.credentials.json`、Session Storage、transcript、history 與對話 payload 讀取模式的禁止項目掃描。這些掃描不能取代專業安全稽核，但可防止常見的回歸錯誤。

## 回報安全問題

請不要在公開 Issue 貼上帳戶識別資訊、API Key、Cookie、CSRF token、完整 session JSONL 或 Claude transcript。回報時只需提供應用程式版本、macOS 版本、provider 名稱、狀態碼與已移除敏感資料的錯誤摘要。
