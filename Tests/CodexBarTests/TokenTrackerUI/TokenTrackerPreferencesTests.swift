import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite("Token Tracker preferences")
struct TokenTrackerPreferencesTests {
    @Test
    func `defaults are Side-only and registry aware`() {
        let store = self.makeStore(available: [.codex, .claude, .deepseek])

        #expect(store.preferences.presentationMode == .side)
        #expect(TokenTrackerPresentationMode.allCases == [.side, .menuBarOnly])
        #expect(store.preferences.visibleProviderIDs == ["codex", "claude", "deepseek"])
        #expect(store.preferences.side.interaction.restingSurface == .handle)
    }

    @Test
    func `untouched defaults reconcile but custom order remains`() {
        let untouched = self.makeStore(available: [.codex, .claude])
        untouched.reconcileAvailableProviderIDs([.codex, .claude, .deepseek])
        #expect(untouched.preferences.visibleProviderIDs == ["codex", "claude", "deepseek"])

        let custom = self.makeStore(available: [.codex, .claude, .deepseek])
        custom.setVisible(false, providerID: .claude)
        custom.reconcileAvailableProviderIDs([.codex, .claude, .deepseek, .cursor])
        #expect(custom.preferences.visibleProviderIDs == ["codex", "deepseek"])
        #expect(custom.preferences.hasCustomizedVisibleProviders)
    }

    @Test
    func `missing plugin IDs remain persisted but not effective`() throws {
        let store = self.makeStore(available: [.codex, .claude])
        store.update {
            $0.visibleProviderIDs = ["future-plugin", "codex", "codex"]
            $0.hasCustomizedVisibleProviders = true
        }

        #expect(store.preferences.visibleProviderIDs == ["future-plugin", "codex"])
        #expect(store.effectiveVisibleProviderIDs == [.codex])
        try store.reconcileAvailableProviderIDs([
            .codex,
            .claude,
            #require(ProviderInstanceID(rawValue: "future-plugin")),
        ])
        #expect(store.effectiveVisibleProviderIDs.map(\.rawValue) == ["future-plugin", "codex"])
    }

    @Test
    func `legacy defaults migrate as untouched and empty remains custom`() throws {
        let legacyDefault = self.makeDefaults()
        try self.writeLegacy(legacyDefault, visible: ["codex", "claude"])
        let migratedDefault = TokenTrackerPreferencesStore(
            userDefaults: legacyDefault,
            availableProviderIDs: [.codex, .claude, .deepseek])
        #expect(!migratedDefault.preferences.hasCustomizedVisibleProviders)
        #expect(migratedDefault.preferences.visibleProviderIDs == ["codex", "claude", "deepseek"])

        let legacyEmpty = self.makeDefaults()
        try self.writeLegacy(legacyEmpty, visible: [])
        let migratedEmpty = TokenTrackerPreferencesStore(
            userDefaults: legacyEmpty,
            availableProviderIDs: [.codex, .claude, .deepseek])
        #expect(migratedEmpty.preferences.hasCustomizedVisibleProviders)
        #expect(migratedEmpty.preferences.visibleProviderIDs.isEmpty)
    }

    @Test
    func `future and corrupt payloads are not overwritten`() throws {
        let futureDefaults = self.makeDefaults()
        var future = TokenTrackerPreferences.defaults(availableProviderIDs: [.codex])
        future.schemaVersion = 99
        let futureData = try JSONEncoder().encode(future)
        futureDefaults.set(futureData, forKey: TokenTrackerPreferencesStore.storageKey)
        let futureStore = TokenTrackerPreferencesStore(userDefaults: futureDefaults, availableProviderIDs: [.codex])
        #expect(futureStore.loadIssue == .unsupportedSchema(99))
        #expect(futureDefaults.data(forKey: TokenTrackerPreferencesStore.storageKey) == futureData)

        let corruptDefaults = self.makeDefaults()
        let corrupt = Data("not-json".utf8)
        corruptDefaults.set(corrupt, forKey: TokenTrackerPreferencesStore.storageKey)
        let corruptStore = TokenTrackerPreferencesStore(userDefaults: corruptDefaults, availableProviderIDs: [.codex])
        #expect(corruptStore.loadIssue == .corruptData)
        #expect(corruptDefaults.data(forKey: TokenTrackerPreferencesStore.storageKey) == corrupt)
    }

    @Test
    func `side snap location survives store recreation`() {
        let defaults = self.makeDefaults()
        let store = TokenTrackerPreferencesStore(userDefaults: defaults, availableProviderIDs: [.codex])
        store.setSideLocation(screenID: "stable-display", edge: .left, normalizedY: 0.73)

        let restored = TokenTrackerPreferencesStore(userDefaults: defaults, availableProviderIDs: [.codex])
        #expect(restored.preferences.side.screenID == "stable-display")
        #expect(restored.preferences.side.edge == .left)
        #expect(restored.preferences.side.normalizedY == 0.73)
    }

    @Test
    func `all settings survive complete store recreation`() {
        let defaults = self.makeDefaults()
        let store = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])
        store.update {
            $0.presentationMode = .side
            $0.visibleProviderIDs = ["deepseek", "codex"]
            $0.hasCustomizedVisibleProviders = true

            $0.side.screenID = "side-screen"
            $0.side.edge = .left
            $0.side.normalizedY = 0.81
            $0.side.interaction.restingSurface = .providers
            $0.side.interaction.persistentProviderID = "codex"
            $0.side.interaction.lastOpenedProviderID = "deepseek"
            $0.side.interaction.openAction = .none
            $0.side.interaction.providerClickAction = .openProviderSettings
            $0.side.interaction.openDelay = 0.3
            $0.side.interaction.closeDelay = 0.8
            $0.side.railSize = .compact

        }
        let expected = store.preferences

        let restored = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])

        #expect(restored.preferences == expected)
        #expect(restored.loadIssue == nil)
    }

    @Test(arguments: [TokenTrackerPresentationMode.notch, .bottom])
    func `legacy presentation selections migrate to Side`(legacyMode: TokenTrackerPresentationMode) throws {
        let defaults = self.makeDefaults()
        var legacy = TokenTrackerPreferences.defaults(availableProviderIDs: [.codex])
        legacy.schemaVersion = 2
        legacy.presentationMode = legacyMode
        defaults.set(try JSONEncoder().encode(legacy), forKey: TokenTrackerPreferencesStore.storageKey)

        let store = TokenTrackerPreferencesStore(userDefaults: defaults, availableProviderIDs: [.codex])
        #expect(store.preferences.presentationMode == .side)
        #expect(store.preferences.schemaVersion == TokenTrackerPreferences.currentSchemaVersion)
    }

    @Test
    func `drag reorder persists while preserving unavailable provider slots`() throws {
        let defaults = self.makeDefaults()
        let future = try #require(ProviderInstanceID(rawValue: "future-plugin"))
        let store = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])
        store.update {
            $0.visibleProviderIDs = [future.rawValue, "codex", "claude", "deepseek"]
            $0.hasCustomizedVisibleProviders = true
        }

        store.moveVisibleProviders(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(store.preferences.visibleProviderIDs == ["future-plugin", "claude", "deepseek", "codex"])
        #expect(store.effectiveVisibleProviderIDs == [.claude, .deepseek, .codex])
        let restored = TokenTrackerPreferencesStore(
            userDefaults: defaults,
            availableProviderIDs: [.codex, .claude, .deepseek])
        #expect(restored.preferences.visibleProviderIDs == ["future-plugin", "claude", "deepseek", "codex"])
    }

    private func makeStore(available: [ProviderInstanceID]) -> TokenTrackerPreferencesStore {
        TokenTrackerPreferencesStore(userDefaults: self.makeDefaults(), availableProviderIDs: available)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "TokenTrackerPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func writeLegacy(_ defaults: UserDefaults, visible: [String]) throws {
        let current = TokenTrackerPreferences.defaults(availableProviderIDs: [.codex, .claude])
        let data = try JSONEncoder().encode(current)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "hasCustomizedVisibleProviders")
        object["visibleProviderIDs"] = visible
        try defaults.set(
            JSONSerialization.data(withJSONObject: object),
            forKey: TokenTrackerPreferencesStore.storageKey)
    }
}
