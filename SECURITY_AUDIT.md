# 公開發布前資安稽核報告

**稽核日期：2026-09-04**  
**稽核範圍：Git 完整歷史、目前追蹤檔案、v0.1.1 Release App ZIP、Source ZIP、Checksum、App binary 與打包流程**

## 結論

本次稽核沒有發現任何實際 **Anthropic/OpenAI/Google API Key、GitHub Token、私鑰、密碼、Cookie、瀏覽器 Session、憑證檔、Claude transcript、Codex 對話內容或 Antigravity CSRF Token** 被提交或打包。v0.1.1 App binary 未包含開發者的絕對建置路徑，Release Checksum 亦驗證成功。

> **公開風險判定：可在完成文件路徑清理與新版安全掃描整合後公開。** 目前 Repository 仍維持 Private，尚未執行 visibility 變更。

## 稽核結果

| 項目 | 結果 | 說明 |
|---|---:|---|
| Git 歷史 Secret pattern | PASS | 全部 Commit 未偵測到實際 API Key、GitHub Token、雲端金鑰或私鑰內容 |
| 敏感檔名 | PASS | 未追蹤 `.env`、credentials JSON、PEM、P8、P12、SSH private key 或 provisioning profile |
| v0.1.1 Source ZIP | PASS | 未偵測到 Secret pattern 或敏感資料檔 |
| v0.1.1 App ZIP | PASS | Bundle 只包含 Info.plist、Mach-O executable 與 CodeResources |
| App binary 絕對路徑 | PASS | 未包含 `/Users/...` 或 `/home/...` build path |
| AI 對話資料 | PASS | 沒有 transcript、Prompt、回覆內容或 Codex history 資料被打包 |
| Keychain 資料 | PASS | Keychain 只在執行時透過 Security framework 讀寫，沒有匯出到專案或 Release |
| Antigravity CSRF | PASS | CSRF Token 只存在於執行時記憶體，沒有寫入 log、cache、Git 或 Release |
| Release SHA-256 | PASS | App ZIP 與 Source ZIP 都通過發布 Checksum 回驗 |
| 文件絕對路徑 | 已修正 | README、RELEASING 與 TEST_REPORT 的個人路徑已改為 `/path/to/AIUsageMonitor` |

## 資料最小化確認

應用程式的 Claude provider 只解碼 quota、Token、Context、模型與費用欄位，不讀取 `.credentials.json` 或 transcript。Codex provider 只處理 `token_count` 的數值事件，不解析對話內容。Antigravity provider 只將本機 CSRF Token 用於 loopback request，且不持久化。Anthropic 與 OpenAI 管理金鑰只儲存在 macOS Keychain。

新增的 GitHub 更新檢查將只讀取 Public Release 的 `tag_name`、`name`、`body`、`html_url`、`published_at`、`prerelease` 與公開下載連結，不使用 GitHub Token，也不傳送本機 AI 用量、裝置識別碼或使用者資料。

## 公開前必要控制

在變更 Repository visibility 前，必須再次完成目前 HEAD Secret 掃描、Git 歷史 Secret 掃描、Release Source ZIP 掃描、App binary 絕對路徑掃描與 SHA-256 驗證。發布腳本亦應在建立 GitHub Release 前自動執行這些檢查，任一項失敗就中止發布。
