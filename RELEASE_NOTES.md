# AI Usage Monitor v0.2.0

## 新功能

本版本新增 **GitHub Release 更新通知**。應用程式會在啟動後與設定間隔到期時，唯讀檢查 `Shawn66168/AI-Usage-Monitor` 的最新正式 Release。若遠端版本高於目前版本，macOS 選單列會顯示 `NEW`，展開後可查看版本摘要、略過該版本，或開啟 GitHub Release 頁面。

設定視窗新增「更新」分頁，可啟用或停用自動檢查，並選擇每 6、12 或 24 小時檢查。手動檢查會忽略既有 ETag 強制取得最新 metadata；背景檢查則使用 ETag conditional request，收到 `304 Not Modified` 時沿用安全快取。

## 資安與隱私

更新檢查不使用 GitHub Token，亦不擷取 Cookie。網路層使用停用 Cookie、無 URL cache 的 ephemeral session，只允許固定 GitHub REST endpoint；使用者可開啟的 Release URL 必須是 HTTPS 且符合指定 Repository path 白名單。

應用程式只快取公開 Release 版本、名稱、說明、發布時間、URL 與 ETag，不會傳送 AI 用量、Token、Context、帳戶資料、裝置識別碼或 macOS 使用者名稱。本版本只提供更新提示，不會自動下載、解壓或執行遠端檔案。

新增 `Scripts/security_audit.sh`，每次測試會掃描目前原始碼、Git 完整歷史、敏感檔名與個人絕對路徑；正式發布前還會解壓 App／Source ZIP，檢查 Secret、憑證、Cookie、binary build path 與打包內容。任一項失敗時發布腳本會在推送 GitHub 前中止。

## 測試與驗證

| 項目 | 結果 |
|---|---:|
| 既有核心單元測試 | 5 組通過 |
| 更新檢查單元測試 | 7 組通過 |
| Swift 6 Release warnings-as-errors | 通過 |
| Claude／Codex 實機 provider 診斷 | 通過 |
| Repository 與 Git 歷史 Secret 掃描 | 通過 |
| Release App／Source ZIP 資安掃描 | 通過 |
| SHA-256 回驗 | 通過 |
| App ad-hoc codesign 驗證 | 通過 |
| Apple Silicon arm64 啟動測試 | 通過 |

## 已知限制

此版本的更新資料來源必須是 Public GitHub Repository。更新按鈕只會開啟 GitHub Release 頁面，不會在 App 內直接安裝新版。正式對外散布仍建議使用 Apple Developer ID 簽章與 notarization；目前 ZIP 採 ad-hoc 簽章，首次開啟可能需要由 macOS「隱私權與安全性」核准。
