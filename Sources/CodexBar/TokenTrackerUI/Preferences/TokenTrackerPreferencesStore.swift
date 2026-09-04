import CodexBarCore
import Foundation
import Observation

@MainActor
@Observable
final class TokenTrackerPreferencesStore {
    static let storageKey = "tokenTracker.preferences"

    private(set) var preferences: TokenTrackerPreferences
    private(set) var loadIssue: LoadIssue?
    private(set) var catalogRevision = 0

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var availableProviderIDs: [ProviderInstanceID]

    enum LoadIssue: Equatable {
        case corruptData
        case unsupportedSchema(Int)
    }

    init(userDefaults: UserDefaults, availableProviderIDs: [ProviderInstanceID]) {
        self.userDefaults = userDefaults
        self.availableProviderIDs = availableProviderIDs
        let result = Self.load(from: userDefaults, availableProviderIDs: availableProviderIDs)
        self.preferences = result.preferences
        self.loadIssue = result.issue
        if result.shouldPersist {
            self.persist()
        }
    }

    var effectiveVisibleProviderIDs: [ProviderInstanceID] {
        Self.effectiveVisibleProviderIDs(
            stored: self.preferences.visibleProviderIDs,
            availableProviderIDs: self.availableProviderIDs)
    }

    func reconcileAvailableProviderIDs(_ providerIDs: [ProviderInstanceID]) {
        if providerIDs != self.availableProviderIDs {
            self.catalogRevision &+= 1
        }
        self.availableProviderIDs = providerIDs
        guard !self.preferences.hasCustomizedVisibleProviders else { return }
        let defaults = TokenTrackerDefaultProviders.resolve(in: providerIDs).map(\.rawValue)
        guard defaults != self.preferences.visibleProviderIDs else { return }
        self.preferences.visibleProviderIDs = defaults
        self.reconcileDefaultProviders()
        self.persist()
    }

    func update(_ mutate: (inout TokenTrackerPreferences) -> Void) {
        mutate(&self.preferences)
        self.preferences = Self.normalized(self.preferences)
        self.persist()
    }

    func setVisible(_ isVisible: Bool, providerID: ProviderInstanceID) {
        self.update { preferences in
            preferences.hasCustomizedVisibleProviders = true
            preferences.visibleProviderIDs.removeAll { $0 == providerID.rawValue }
            if isVisible {
                preferences.visibleProviderIDs.append(providerID.rawValue)
            }
        }
    }

    func moveVisibleProvider(_ providerID: ProviderInstanceID, direction: Int) {
        guard direction != 0,
              let source = self.preferences.visibleProviderIDs.firstIndex(of: providerID.rawValue)
        else { return }
        let destination = min(max(0, source + direction), self.preferences.visibleProviderIDs.count - 1)
        guard destination != source else { return }
        self.update { preferences in
            preferences.hasCustomizedVisibleProviders = true
            preferences.visibleProviderIDs.swapAt(source, destination)
        }
    }

    func moveVisibleProviders(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = self.effectiveVisibleProviderIDs.map(\.rawValue)
        let validOffsets = fromOffsets.filter { reordered.indices.contains($0) }
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { reordered[$0] }
        for offset in validOffsets.sorted(by: >) {
            reordered.remove(at: offset)
        }
        let removedBeforeDestination = validOffsets.count(where: { $0 < toOffset })
        let destination = min(max(0, toOffset - removedBeforeDestination), reordered.count)
        reordered.insert(contentsOf: moving, at: destination)

        let available = Set(self.effectiveVisibleProviderIDs.map(\.rawValue))
        var reorderedIterator = reordered.makeIterator()
        self.update { preferences in
            preferences.hasCustomizedVisibleProviders = true
            preferences.visibleProviderIDs = preferences.visibleProviderIDs.map { raw in
                available.contains(raw) ? (reorderedIterator.next() ?? raw) : raw
            }
        }
    }

    func setSideLocation(screenID: String?, edge: TokenTrackerHorizontalEdge, normalizedY: Double) {
        self.update { preferences in
            preferences.side.screenID = screenID
            preferences.side.edge = edge
            preferences.side.normalizedY = normalizedY
        }
    }

    private func reconcileDefaultProviders() {
        let first = self.preferences.visibleProviderIDs.first
        if self.preferences.notch.defaultProviderID == nil {
            self.preferences.notch.defaultProviderID = first
        }
        if self.preferences.side.interaction.persistentProviderID == nil {
            self.preferences.side.interaction.persistentProviderID = first
        }
        if self.preferences.bottom.interaction.persistentProviderID == nil {
            self.preferences.bottom.interaction.persistentProviderID = first
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(self.preferences) else { return }
        self.userDefaults.set(data, forKey: Self.storageKey)
        self.loadIssue = nil
    }
}

extension TokenTrackerPreferencesStore {
    private struct LegacyPreferences: Codable {
        var schemaVersion: Int
        var presentationMode: TokenTrackerPresentationMode
        var visibleProviderIDs: [String]
        var notch: TokenTrackerNotchPreferences
        var side: TokenTrackerSidePreferences
        var bottom: TokenTrackerBottomPreferences
    }

    private struct LoadResult {
        let preferences: TokenTrackerPreferences
        let issue: LoadIssue?
        let shouldPersist: Bool
    }

    private static func load(
        from userDefaults: UserDefaults,
        availableProviderIDs: [ProviderInstanceID]) -> LoadResult
    {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return LoadResult(
                preferences: .defaults(availableProviderIDs: availableProviderIDs),
                issue: nil,
                shouldPersist: true)
        }

        let decoder = JSONDecoder()
        if let current = try? decoder.decode(TokenTrackerPreferences.self, from: data) {
            guard current.schemaVersion <= TokenTrackerPreferences.currentSchemaVersion else {
                return LoadResult(
                    preferences: .defaults(availableProviderIDs: availableProviderIDs),
                    issue: .unsupportedSchema(current.schemaVersion),
                    shouldPersist: false)
            }
            var normalized = Self.normalized(current)
            normalized.schemaVersion = TokenTrackerPreferences.currentSchemaVersion
            if !normalized.hasCustomizedVisibleProviders {
                normalized.visibleProviderIDs = TokenTrackerDefaultProviders.resolve(in: availableProviderIDs)
                    .map(\.rawValue)
            }
            return LoadResult(preferences: normalized, issue: nil, shouldPersist: normalized != current)
        }

        if let legacy = try? decoder.decode(LegacyPreferences.self, from: data), legacy.schemaVersion == 1 {
            let customized = Self.legacyVisibleProvidersWereCustomized(
                legacy.visibleProviderIDs,
                availableProviderIDs: availableProviderIDs)
            let visible = customized
                ? legacy.visibleProviderIDs
                : TokenTrackerDefaultProviders.resolve(in: availableProviderIDs).map(\.rawValue)
            let migrated = TokenTrackerPreferences(
                schemaVersion: TokenTrackerPreferences.currentSchemaVersion,
                presentationMode: legacy.presentationMode,
                visibleProviderIDs: visible,
                hasCustomizedVisibleProviders: customized,
                notch: legacy.notch,
                side: legacy.side,
                bottom: legacy.bottom)
            return LoadResult(preferences: Self.normalized(migrated), issue: nil, shouldPersist: true)
        }

        return LoadResult(
            preferences: .defaults(availableProviderIDs: availableProviderIDs),
            issue: .corruptData,
            shouldPersist: false)
    }

    static func effectiveVisibleProviderIDs(
        stored: [String],
        availableProviderIDs: [ProviderInstanceID]) -> [ProviderInstanceID]
    {
        let available = Set(availableProviderIDs)
        var seen = Set<ProviderInstanceID>()
        return stored.compactMap(ProviderInstanceID.init(rawValue:)).filter { id in
            available.contains(id) && seen.insert(id).inserted
        }
    }

    private static func legacyVisibleProvidersWereCustomized(
        _ stored: [String],
        availableProviderIDs: [ProviderInstanceID]) -> Bool
    {
        guard !stored.isEmpty else { return true }
        let available = Set(availableProviderIDs)
        // Provider-specific by design: these are the two shipped default sets whose migration preserves intent.
        let historicalDefaults: [[ProviderInstanceID]] = [
            [.codex, .claude],
            [.codex, .claude, .deepseek],
        ]
        return !historicalDefaults.contains { candidates in
            candidates.filter { available.contains($0) }.map(\.rawValue) == stored
        }
    }

    private static func normalized(_ input: TokenTrackerPreferences) -> TokenTrackerPreferences {
        var value = input
        value.schemaVersion = TokenTrackerPreferences.currentSchemaVersion
        if value.presentationMode == .notch || value.presentationMode == .bottom {
            value.presentationMode = .side
        }
        var seen = Set<String>()
        value.visibleProviderIDs = value.visibleProviderIDs.filter { raw in
            ProviderInstanceID(rawValue: raw) != nil && seen.insert(raw).inserted
        }
        value.notch.openDelay = Self.delay(value.notch.openDelay, fallback: 0.15)
        value.notch.closeDelay = Self.delay(value.notch.closeDelay, fallback: 0.45)
        value.side.normalizedY = Self.clamp(value.side.normalizedY, fallback: 0.5)
        value.side.interaction = Self.normalized(value.side.interaction)
        value.bottom.gap = min(12, max(8, value.bottom.gap.isFinite ? value.bottom.gap : 10))
        if let x = value.bottom.calibratedDockBoundaryNormalizedX {
            value.bottom.calibratedDockBoundaryNormalizedX = Self.clamp(x, fallback: 0.5)
        }
        value.bottom.interaction = Self.normalized(value.bottom.interaction)
        return value
    }

    private static func normalized(
        _ input: TokenTrackerEdgeInteractionPreferences) -> TokenTrackerEdgeInteractionPreferences
    {
        var value = input
        value.openDelay = Self.delay(value.openDelay, fallback: 0.15)
        value.closeDelay = Self.delay(value.closeDelay, fallback: 0.45)
        return value
    }

    private static func delay(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : fallback
    }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        min(1, max(0, value.isFinite ? value : fallback))
    }
}
