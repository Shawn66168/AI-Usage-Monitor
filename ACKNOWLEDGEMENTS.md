# Acknowledgements

AI Usage Monitor 的實作過程參考了下列開源專案公開揭露的整合方向。主程式以原生 Swift 重新建立資料模型、狀態管理、安全層、UI、快取、通知、登入項目與測試，不包含任何第三方帳戶憑證或私人資料。

| 專案 | 參考重點 | 連結 |
|---|---|---|
| Antigravity-Usage-Tracker | 從執行中的 Antigravity Language Server 探索 loopback port，並呼叫 `GetUserStatus` 取得模型 quota 的整合方向 | https://github.com/timbeh/Antigravity-Usage-Tracker |
| codex-quota-widget | 透過 Codex `app-server` 的 `account/rateLimits/read` 取得五小時與每週 quota，以及只從 session JSONL 的 `token_count` 事件彙總 Token 的整合方向 | https://github.com/1nuYasha-cck/codex-quota-widget |
| antigravity-usage | Antigravity quota 的本機與 CLI 使用情境、quota refresh 與模型 bucket 概念 | https://github.com/skainguyen1412/antigravity-usage |

感謝上述維護者公開其研究與實作。若這些專案對你有幫助，請造訪其 GitHub repository 並考慮給予 Star，以支持維護者持續更新。

Apple、macOS、Swift、SwiftUI 與 Keychain 為 Apple Inc. 的商標或技術。Claude 與 Anthropic 為 Anthropic 相關名稱；ChatGPT、Codex 與 OpenAI 為 OpenAI 相關名稱；Antigravity 與 Google 為 Google 相關名稱；Manus 為其權利人之相關名稱。本專案與上述服務提供者沒有隸屬或官方背書關係。
