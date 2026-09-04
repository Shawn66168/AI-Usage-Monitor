# GitHub Releases 發布手冊

**作者：Manus AI**

AI Usage Monitor 使用 `Scripts/publish_github_release.sh` 在開發者的 Mac 本機完成測試、Release build、版本化資產、Git Tag 與 GitHub Release。腳本強制要求 `--repo OWNER/REPOSITORY`，不會從其他已連線專案推測發布目標，藉此降低誤發到錯誤 Repository 的風險。

> 腳本預設不建立 Repository。若目標尚不存在，必須明確加入 `--create-repo`；新 Repository 預設為 Private，只有明確加入 `--visibility public` 才會建立 Public Repository。

## 發布流程

| 階段 | 腳本行為 | 失敗時的保護 |
|---|---|---|
| 前置檢查 | 驗證 macOS 指令、GitHub CLI 登入、Repository 格式、SemVer、Release Notes 與乾淨 Git 工作目錄 | 任一檢查失敗立即中止，不執行遠端修改 |
| 目標確認 | 以 `gh repo view --repo` 概念確認指定 Repository；既有 Release、Local Tag 與 Remote Tag 均檢查衝突 | 不覆寫既有 Release，不移動既有 Tag |
| 品質驗證 | 執行單元測試、實機 Provider 診斷、Swift 6 warnings-as-errors、隱私路徑與 Secret 掃描 | 預設不可略過；只有明確加入 `--skip-tests` 才會跳過 |
| 打包 | 將 `VERSION` 與 `BUILD_NUMBER` 傳給 `build_app.sh`，產生版本化 App ZIP | Info.plist、codesign 與輸出檔均再次驗證 |
| 發布資產 | 從已提交的 `HEAD` 建立 Source ZIP，並為 App ZIP 與 Source ZIP 產生 SHA-256 清單 | Source ZIP 不包含未提交檔案、`.git`、`.build` 或 `Build` |
| 遠端發布 | 推送目前分支、建立 Annotated Tag、推送 Tag，再用 GitHub CLI 建立 Release | `--verify-tag` 確保 GitHub Release 綁定已存在的遠端 Tag；不由 GitHub 自動猜測 Tag 來源 [1] |

## 必要條件

必須先安裝並登入 GitHub CLI，且 Token 需具備目標 Repository 的寫入權限。可用下列指令檢查：

```bash
gh auth status
```

GitHub CLI 的 `release create` 支援 `--repo` 指定 Repository、`--verify-tag` 驗證遠端 Tag、`--notes-file` 載入 Markdown 說明，以及直接上傳 Release assets。[1] Repository 尚不存在時，腳本可呼叫 `gh repo create` 建立 Private 或 Public Repository。[2]

## 第一次發布前的準備

請先確認所有程式碼與 Release Notes 都已提交。腳本會拒絕在工作目錄有未提交變更時執行，避免 Source ZIP 與 App binary 使用不同內容。

```bash
cd "/path/to/AIUsageMonitor"

git status
git log -1 --oneline
gh auth status
```

接著更新 `RELEASE_NOTES.md`，內容必須明確包含要發布的版本號。例如要發布 `0.1.1`，文件中必須出現 `0.1.1`。這是腳本的版本一致性防呆。

## 先執行 Dry Run

目前 `Shawn66168/AI-Usage-Monitor` 尚未存在，因此第一次建議先執行：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.1 \
  --create-repo \
  --dry-run
```

Dry Run **仍會執行測試與本機打包**，用來確認實際 Release 資產可以產生；但它不會建立 Repository、不會 Push branch 或 Tag，也不會建立 GitHub Release。最後會逐行顯示原本預計執行的遠端命令。

成功後應在 `Build/` 看到以下檔案：

```text
AI-Usage-Monitor-macOS-arm64-v0.1.1.zip
AI-Usage-Monitor-Source-v0.1.1.zip
SHA256SUMS-v0.1.1.txt
```

可用下列方式重新驗證下載資產：

```bash
cd Build
shasum -a 256 -c SHA256SUMS-v0.1.1.txt
```

## 正式建立 Private Repository 並發布

確認 Dry Run 通過後，移除 `--dry-run`：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.1 \
  --create-repo
```

第一次執行會建立 Private Repository、推送目前分支、建立並推送 `v0.1.1` Annotated Tag，最後發布三個 assets。日後 Repository 已存在時，不必再加入 `--create-repo`：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.2
```

若確定要建立 Public Repository，第一次執行才加入：

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.1.1 \
  --create-repo \
  --visibility public
```

## Draft 與 Prerelease

正式發布前想先檢查 GitHub 畫面，可加入 `--draft`。Draft Release 不會以一般正式 Release 對外呈現，確認後再於 GitHub 手動 Publish。[1]

```bash
./Scripts/publish_github_release.sh \
  --repo Shawn66168/AI-Usage-Monitor \
  --version 0.2.0-beta.1 \
  --draft
```

只要版本包含 `-`，例如 `0.2.0-beta.1`，腳本會自動加入 Prerelease；也可對一般版本明確加入 `--prerelease`。

## 完整參數

| 參數 | 必要 | 說明 |
|---|---:|---|
| `--repo OWNER/REPOSITORY` | 是 | 強制指定唯一發布目標，例如 `Shawn66168/AI-Usage-Monitor` |
| `--version X.Y.Z` | 是 | 不含 `v` 的 SemVer；Git Tag 會自動加上 `v` |
| `--build-number N` | 否 | 覆寫 `CFBundleVersion`；預設使用 Git commit count |
| `--notes-file PATH` | 否 | 預設為專案根目錄 `RELEASE_NOTES.md` |
| `--create-repo` | 否 | 目標不存在時建立 Repository；未指定則安全中止 |
| `--visibility private\|public` | 否 | 只在 `--create-repo` 時使用，預設 `private` |
| `--draft` | 否 | 建立 Draft Release |
| `--prerelease` | 否 | 標記為 Prerelease |
| `--skip-tests` | 否 | 跳過測試，不建議在正式發布使用 |
| `--dry-run` | 否 | 完成本機測試與打包，只預覽遠端修改 |
| `--help` | 否 | 顯示指令說明 |

## 重跑與故障恢復

如果分支已推送但 Tag 尚未推送，修正錯誤後可用相同版本重跑；腳本會辨認目前狀態並繼續。如果 Local Tag 或 Remote Tag 已存在，腳本只允許它指向目前 `HEAD`。若指向其他 commit，腳本會安全中止，不會強制移動 Tag。

如果 GitHub Release 已存在，腳本不會覆寫或替換 assets。請先決定是要在 GitHub 手動維護該 Release，或增加版本號重新發布。這項設計也相容啟用 Immutable Releases 的 Repository，因為已發布後的 Tag 與 assets 不應被修改。[1]

## 不會自動執行的行為

腳本不會自動變更 Repository visibility、不會刪除 Release、不會刪除或強制移動 Tag、不會修改 GitHub Secrets，也不會把 API 金鑰、Keychain 或本機 AI 用量資料放進 Source ZIP。發布是一項會改變遠端狀態的明確操作，因此正式指令必須由使用者自行執行。

## References

[1]: https://cli.github.com/manual/gh_release_create "GitHub CLI Manual — gh release create"
[2]: https://cli.github.com/manual/gh_repo_create "GitHub CLI Manual — gh repo create"
