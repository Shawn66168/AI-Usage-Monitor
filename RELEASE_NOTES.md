# AI Usage Monitor v0.2.1

## 變更摘要

本版本將 **Anthropic Usage／Cost Admin API** 與 **OpenAI Organization Usage／Costs API** 從本機高頻刷新排程中分離，兩個管理 API 現在各自採用 **15 分鐘最小刷新間隔**。Claude Code、Codex 與 Antigravity 等本機資料來源仍依設定頁的 30 秒至 15 分鐘頻率更新，因此不會犧牲選單列的即時使用體驗。

## 刷新行為

| 操作 | 本機 Provider | Anthropic／OpenAI Admin API |
|---|---:|---:|
| 背景自動刷新 | 依使用者設定 | 最多每 15 分鐘一次 |
| 選單列「更新用量」 | 立即更新 | 未滿 15 分鐘時沿用既有資料 |
| 新增管理金鑰 | 不受影響 | 強制刷新對應 API 一次 |
| 移除管理金鑰 | 不受影響 | 強制刷新對應 Provider 狀態一次 |
| App 重新啟動且已有快取 | 立即讀取本機資料 | 以快取時間延續 15 分鐘保護 |

刷新閘門以 service 為單位獨立記錄時間，Anthropic 與 OpenAI 不會互相阻擋。管理 API 被略過時，介面會保留最近成功的非敏感快照，不會將卡片清空或改成錯誤狀態。

## 安全與相容性

管理金鑰仍只保存在 macOS Keychain；本次變更不新增 Token、Cookie 或對話資料儲存。15 分鐘政策只降低 Usage／Cost 報表請求頻率，不會呼叫模型或產生推論 Token。

## 測試結果

| 項目 | 結果 |
|---|---:|
| 核心單元測試 | 6 組通過 |
| Admin API 最小間隔為 900 秒 | 通過 |
| 15 分鐘前拒絕重複刷新 | 通過 |
| 15 分鐘到期後允許刷新 | 通過 |
| Anthropic／OpenAI 獨立閘門 | 通過 |
| 憑證變更強制刷新 | 通過 |
| 本機 Provider 每輪刷新 | 通過 |
| GitHub 更新測試 | 7 組通過 |
| Swift 6 warnings-as-errors | 通過 |
| Repository 與 Git 歷史 Secret 掃描 | 通過 |
| v0.2.1 App ZIP 資安掃描 | 通過 |
| arm64、Info.plist 與 codesign | 通過 |

## 已知限制

本版本提供固定 15 分鐘的本機保護，但尚未解析 HTTP 429 的 `Retry-After` 或供應商 rate-limit reset headers。若伺服器要求超過 15 分鐘的等待時間，下一版仍應加入 per-provider cooldown 與錯誤類型分類。
