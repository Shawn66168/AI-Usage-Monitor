import AppKit
import SwiftUI

@main
struct AIUsageMonitorApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var updateStore: AppUpdateStore

    init() {
        let providers: [any UsageProvider] = [
            ClaudeProvider(),
            CodexProvider(),
            AntigravityProvider(),
            UnsupportedProvider(
                kind: .chatGPT,
                reason: "個人 ChatGPT 模型目前沒有穩定的官方用量 API",
                sourceDescription: "官方未提供"
            ),
            UnsupportedProvider(
                kind: .manus,
                reason: "等待官方提供正式個人用量資料來源",
                sourceDescription: "官方資料來源待確認"
            ),
            AnthropicAdminProvider(),
            OpenAIAdminProvider()
        ]

        _store = StateObject(wrappedValue: UsageStore(providers: providers))
        _updateStore = StateObject(wrappedValue: AppUpdateStore())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store, updateStore: updateStore)
                .task {
                    store.start()
                    updateStore.start()
                }
        } label: {
            MenuBarLabel(store: store, updateStore: updateStore)
                .task {
                    store.start()
                    updateStore.start()
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AI Usage Monitor", id: "dashboard") {
            DashboardView(store: store)
                .task {
                    store.start()
                    updateStore.start()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(store: store, updateStore: updateStore)
        }
    }
}
