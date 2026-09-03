import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem {
                    Label("一般", systemImage: "gearshape")
                }

            DataSourceSettingsView(store: store)
                .tabItem {
                    Label("資料來源", systemImage: "externaldrive.connected.to.line.below")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("隱私", systemImage: "hand.raised.fill")
                }
        }
        .frame(width: 640, height: 470)
        .padding(16)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("自動更新") {
                Picker("更新頻率", selection: refreshIntervalBinding) {
                    Text("30 秒").tag(TimeInterval(30))
                    Text("1 分鐘").tag(TimeInterval(60))
                    Text("2 分鐘").tag(TimeInterval(120))
                    Text("5 分鐘").tag(TimeInterval(300))
                    Text("15 分鐘").tag(TimeInterval(900))
                }
                .pickerStyle(.menu)

                LaunchAtLoginControl(store: store)
            }

            Section("低用量通知") {
                Toggle("啟用系統通知", isOn: notificationsBinding)
                HStack {
                    Text("剩餘用量低於")
                    Slider(value: thresholdBinding, in: 5 ... 50, step: 5)
                    Text("\(Int(store.preferences.notificationThresholdPercent))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                .disabled(!store.preferences.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var refreshIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { store.preferences.refreshIntervalSeconds },
            set: { value in
                var preferences = store.preferences
                preferences.refreshIntervalSeconds = value
                store.preferences = preferences
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.notificationsEnabled },
            set: { value in
                var preferences = store.preferences
                preferences.notificationsEnabled = value
                store.preferences = preferences
            }
        )
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { store.preferences.notificationThresholdPercent },
            set: { value in
                var preferences = store.preferences
                preferences.notificationThresholdPercent = value
                store.preferences = preferences
            }
        )
    }
}

private struct LaunchAtLoginControl: View {
    @ObservedObject var store: UsageStore
    @State private var isEnabled = false
    @State private var statusText = "讀取系統狀態中"
    @State private var errorText: String?
    private let manager = LaunchAtLoginManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("登入後自動啟動", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    updateRegistration(newValue)
                }
            ))
            Text(errorText ?? statusText)
                .font(.caption)
                .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
        }
        .onAppear {
            synchronize()
        }
    }

    private func synchronize() {
        isEnabled = manager.isRegistered
        statusText = manager.statusDescription
        var preferences = store.preferences
        preferences.launchAtLoginEnabled = isEnabled
        store.preferences = preferences
    }

    private func updateRegistration(_ requested: Bool) {
        do {
            try manager.setEnabled(requested)
            isEnabled = manager.isRegistered || requested
            statusText = manager.statusDescription
            errorText = nil

            var preferences = store.preferences
            preferences.launchAtLoginEnabled = isEnabled
            store.preferences = preferences
        } catch {
            isEnabled = manager.isRegistered
            statusText = manager.statusDescription
            errorText = "設定失敗：\(error.localizedDescription)"
        }
    }
}

private struct DataSourceSettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("顯示") {
                Toggle("顯示 API 組織用量卡片", isOn: showAPIServicesBinding)
                Text("API 組織用量與 Claude／ChatGPT 個人訂閱額度是不同資料池，應用程式會分開標示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("本機來源") {
                DataSourceRow(
                    title: "Claude Code",
                    detail: "~/.claude/usage-status.json",
                    symbol: ServiceKind.claude.symbolName,
                    tint: ServiceKind.claude.tint
                )
                DataSourceRow(
                    title: "Codex",
                    detail: "官方 app-server 與 token_count session 事件",
                    symbol: ServiceKind.codex.symbolName,
                    tint: ServiceKind.codex.tint
                )
                DataSourceRow(
                    title: "Antigravity",
                    detail: "執行中的本機 Language Server quota",
                    symbol: ServiceKind.antigravity.symbolName,
                    tint: ServiceKind.antigravity.tint
                )
            }

            Section("官方管理 API") {
                CredentialEditor(
                    kind: .anthropicAdminKey,
                    placeholder: "sk-ant-admin…",
                    store: store
                )
                CredentialEditor(
                    kind: .openAIAdminKey,
                    placeholder: "OpenAI Organization Admin Key",
                    store: store
                )
                Text("金鑰只會寫入此 Mac 的 Keychain。管理 API 顯示的是 API 組織用量與費用，不是個人 Claude／ChatGPT 訂閱額度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var showAPIServicesBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showAPIServices },
            set: { value in
                var preferences = store.preferences
                preferences.showAPIServices = value
                store.preferences = preferences
            }
        )
    }
}

private struct DataSourceRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock.open.display")
                .foregroundStyle(.secondary)
                .help("本機唯讀")
        }
        .padding(.vertical, 3)
    }
}

private struct CredentialEditor: View {
    let kind: CredentialKind
    let placeholder: String
    @ObservedObject var store: UsageStore

    @State private var input = ""
    @State private var isConfigured = false
    @State private var feedback: String?
    private let keychain = KeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(isConfigured ? "已安全儲存於 Keychain" : "尚未設定")
                        .font(.caption)
                        .foregroundStyle(isConfigured ? .green : .secondary)
                }
                Spacer()
                if isConfigured {
                    Button("移除", role: .destructive) {
                        removeCredential()
                    }
                }
            }

            HStack {
                SecureField(placeholder, text: $input)
                    .textFieldStyle(.roundedBorder)
                Button(isConfigured ? "更新" : "儲存") {
                    saveCredential()
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedback.contains("失敗") ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            isConfigured = keychain.contains(kind)
        }
    }

    private func saveCredential() {
        do {
            try keychain.save(input, for: kind)
            input = ""
            isConfigured = true
            feedback = "已儲存，正在刷新 API 組織用量。"
            Task { await store.refreshAll() }
        } catch {
            feedback = "儲存失敗：\(error.localizedDescription)"
        }
    }

    private func removeCredential() {
        do {
            try keychain.delete(kind)
            input = ""
            isConfigured = false
            feedback = "已從 Keychain 移除。"
            Task { await store.refreshAll() }
        } catch {
            feedback = "移除失敗：\(error.localizedDescription)"
        }
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section("隱私優先") {
                Label("不擷取 Cookie 或瀏覽器登入資訊", systemImage: "checkmark.shield.fill")
                Label("不讀取 Prompt、回覆與工具內容", systemImage: "checkmark.shield.fill")
                Label("不將用量資料傳送到第三方伺服器", systemImage: "checkmark.shield.fill")
                Label("管理 API 金鑰只存放於 macOS Keychain", systemImage: "checkmark.shield.fill")
            }

            Section("服務限制") {
                Text("ChatGPT 一般模型與 Manus 個人用量目前不透過不穩定或未授權的網頁爬取取得；這些卡片會清楚標示官方資料來源尚未提供。")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
