# GitHub Release 更新檢查設計

**作者：Manus AI**

## 設計目標

更新檢查採用獨立 `AppUpdateStore`，不混入 AI 用量 provider，避免 GitHub 或網路錯誤影響 quota 刷新。資料來源固定為 Public Repository 的 GitHub REST endpoint：

```text
GET https://api.github.com/repos/Shawn66168/AI-Usage-Monitor/releases/latest
```

GitHub 的 latest endpoint 只回傳最新的正式發布版本，不包含 Draft 或 Prerelease。Request 使用 `Accept: application/vnd.github+json`、固定 API version、明確 `User-Agent`，並保存 `ETag`；後續送出 `If-None-Match`，收到 `304 Not Modified` 時沿用快取，降低 API 請求與流量。[1] 未驗證的 Public REST request 目前以來源 IP 計算，主要限制為每小時 60 次，因此預設每 6 小時自動檢查一次，並提供手動檢查。[2]

| 元件 | 責任 |
|---|---|
| `SemanticVersion` | 正規化 `vX.Y.Z`、比較 major／minor／patch 與 prerelease，不以字串大小誤判 |
| `GitHubReleaseClient` | 唯讀呼叫 latest release endpoint，解碼版本、名稱、說明、發布時間、Release URL 與 App ZIP URL |
| `AppUpdateStore` | 管理目前版本、檢查狀態、最新版、錯誤、上次檢查時間、忽略版本與背景 Task |
| `UpdateCache` | 只保存公開 Release metadata 與 ETag，不保存 Token、Cookie、裝置 ID 或 AI 用量 |
| `MenuBarLabel` | 有新版時以 `arrow.down.circle.fill` 與 `NEW` 提示；否則維持用量狀態 |
| `UpdateAvailableView` | 顯示目前／最新版本、Release Notes 摘要、忽略此版本與開啟 GitHub Release |
| `SettingsView` | 控制自動檢查、6／12／24 小時間隔、手動檢查與清除忽略版本 |

啟動時若超過設定間隔則立即檢查，之後由 App 內背景 Task 定期執行。網路錯誤、404、403／429、格式錯誤與版本錯誤都轉成可讀狀態，不會清除先前已成功取得的公開 metadata，也不會阻塞 AI 用量更新。403／429 不進行密集重試，等待下一個排程或使用者手動操作。

版本更新判定以 App `CFBundleShortVersionString` 為目前版本。只有遠端 `SemanticVersion` 大於本機且不等於使用者忽略版本時，選單列才顯示更新提示。點擊「查看更新」只會透過 `NSWorkspace` 開啟 GitHub Release HTTPS 頁面，不會自動下載、解壓或執行任何遠端檔案。

## 更新檢查資安邊界

此版本只提供通知與 Release 頁面入口，不執行自動安裝，因此不引入 Sparkle、私鑰、Appcast 或下載後執行流程。Request 不包含 GitHub Token；Repository 必須為 Public。應用程式不傳送目前 AI 用量、Token 統計、Context、帳戶資訊、macOS 使用者名稱、本機路徑、硬體識別碼或其他遙測資料。

只有以下公開欄位會寫入 Application Support 快取：

| 欄位 | 用途 |
|---|---|
| `tag_name` | SemVer 比較與忽略版本 |
| `name` | 更新提示標題 |
| `body` | Release Notes 摘要 |
| `html_url` | 使用者主動開啟 GitHub Release |
| `published_at` | 顯示發布日期 |
| `prerelease` | 防禦性過濾 |
| `ETag` | Conditional Request |

## References

[1]: https://docs.github.com/en/rest/releases/releases "GitHub REST API endpoints for releases"
[2]: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api "GitHub REST API rate limits"
