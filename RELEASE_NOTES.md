# AI Usage Monitor 0.1.1

本版本新增一套在 Mac 本機執行的 GitHub Releases 自動發布流程，讓每次版本發布都能使用相同的測試、打包、標籤與資產驗證標準。應用程式核心功能與 0.1.0 相同，主要更新集中於 Release 工程與可重複發布能力。

## 新增功能

| 功能 | 說明 |
|---|---|
| 參數化發布腳本 | 新增 `Scripts/publish_github_release.sh`，強制以 `--repo OWNER/REPOSITORY` 指定唯一 GitHub 目標。 |
| Repository 建立 | 目標不存在時，只有明確加入 `--create-repo` 才會建立；預設為 Private。 |
| Dry Run | 執行完整測試、打包與 Checksum，但不建立 Repository、不 Push、不建立 Tag 或 Release。 |
| 版本化打包 | `build_app.sh` 支援 `VERSION` 與 `BUILD_NUMBER`，並同步寫入 App `Info.plist`。 |
| 發布資產 | 自動產生 Apple Silicon App ZIP、從 committed `HEAD` 建立的 Source ZIP，以及 SHA-256 Checksum 清單。 |
| Git／Release 防呆 | 拒絕 dirty worktree、Detached HEAD、舊版 Release Notes、衝突 Local／Remote Tag，以及已存在的 GitHub Release。 |
| Draft／Prerelease | 支援 `--draft`、`--prerelease`，包含 `-` 的 SemVer 會自動標示為 Prerelease。 |
| 可重跑設計 | 分支或 Tag 已部分推送時，可在指向同一 commit 的前提下安全重跑。 |

## 首次發布指令

先執行不修改 GitHub 的 Dry Run：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.1 \
  --create-repo \
  --dry-run
```

確認通過後移除 `--dry-run`，即可建立 Private Repository 並發布：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.1 \
  --create-repo
```

## 驗證狀態

發布腳本已通過 Bash 語法檢查、完整 Dry Run、缺少 `--repo`、Repository 格式錯誤、版本含錯誤 `v` 前綴、Release Notes 版本不一致、Local Tag 指向錯誤 commit、Source ZIP 禁止路徑、Info.plist 版本、Build Number 及 SHA-256 回驗。

完整操作方式與故障恢復請閱讀 `RELEASING.md`。
