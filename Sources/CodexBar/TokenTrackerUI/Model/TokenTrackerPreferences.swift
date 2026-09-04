import CodexBarCore
import Foundation

struct TokenTrackerPreferences: Codable, Equatable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var presentationMode: TokenTrackerPresentationMode
    var visibleProviderIDs: [String]
    var hasCustomizedVisibleProviders: Bool
    var notch: TokenTrackerNotchPreferences
    var side: TokenTrackerSidePreferences
    var bottom: TokenTrackerBottomPreferences

    static func defaults(availableProviderIDs: [ProviderInstanceID]) -> Self {
        let visible = TokenTrackerDefaultProviders.resolve(in: availableProviderIDs).map(\.rawValue)
        let first = visible.first
        return Self(
            schemaVersion: Self.currentSchemaVersion,
            presentationMode: .side,
            visibleProviderIDs: visible,
            hasCustomizedVisibleProviders: false,
            notch: .defaults(defaultProviderID: first),
            side: .defaults(defaultProviderID: first),
            bottom: .defaults(defaultProviderID: first))
    }
}

enum TokenTrackerPresentationMode: String, Codable, CaseIterable {
    case notch
    case side
    case bottom
    case menuBarOnly

    /// Notch and Bottom remain decodable only so existing local preferences can migrate
    /// into the Side-only product. They are no longer selectable presentation modes.
    static let allCases: [Self] = [.side, .menuBarOnly]
}

struct TokenTrackerNotchPreferences: Codable, Equatable {
    var screenID: String?
    var restingSurface: TokenTrackerNotchRestingSurface
    var defaultProviderID: String?
    var lastOpenedProviderID: String?
    var openAction: TokenTrackerOpenAction
    var providerClickAction: TokenTrackerProviderClickAction
    var openDelay: TimeInterval
    var closeDelay: TimeInterval
    var overviewWidth: TokenTrackerSurfaceSize

    static func defaults(defaultProviderID: String?) -> Self {
        Self(
            screenID: nil,
            restingSurface: .defaultProvider,
            defaultProviderID: defaultProviderID,
            lastOpenedProviderID: nil,
            openAction: .hover,
            providerClickAction: .showDetail,
            openDelay: 0.15,
            closeDelay: 0.45,
            overviewWidth: .standard)
    }
}

enum TokenTrackerNotchRestingSurface: String, Codable, CaseIterable {
    case defaultProvider
    case providers
    case detail
}

struct TokenTrackerSidePreferences: Codable, Equatable {
    var screenID: String?
    var edge: TokenTrackerHorizontalEdge
    var normalizedY: Double
    var interaction: TokenTrackerEdgeInteractionPreferences
    var railSize: TokenTrackerSurfaceSize

    static func defaults(defaultProviderID: String?) -> Self {
        Self(
            screenID: nil,
            edge: .right,
            normalizedY: 0.5,
            interaction: .defaults(defaultProviderID: defaultProviderID),
            railSize: .standard)
    }
}

struct TokenTrackerBottomPreferences: Codable, Equatable {
    var screenID: String?
    var dockSide: TokenTrackerDockCompanionSide
    var gap: Double
    var calibratedDockBoundaryNormalizedX: Double?
    var fallback: TokenTrackerBottomFallback
    var interaction: TokenTrackerEdgeInteractionPreferences
    var shelfSize: TokenTrackerSurfaceSize

    static func defaults(defaultProviderID: String?) -> Self {
        Self(
            screenID: nil,
            dockSide: .leading,
            gap: 10,
            calibratedDockBoundaryNormalizedX: nil,
            fallback: .aboveDock,
            interaction: .defaults(defaultProviderID: defaultProviderID),
            shelfSize: .standard)
    }
}

struct TokenTrackerEdgeInteractionPreferences: Codable, Equatable {
    var restingSurface: TokenTrackerEdgeRestingSurface
    var persistentProviderID: String?
    var lastOpenedProviderID: String?
    var openAction: TokenTrackerOpenAction
    var providerClickAction: TokenTrackerProviderClickAction
    var openDelay: TimeInterval
    var closeDelay: TimeInterval

    static func defaults(defaultProviderID: String?) -> Self {
        Self(
            restingSurface: .handle,
            persistentProviderID: defaultProviderID,
            lastOpenedProviderID: nil,
            openAction: .hover,
            providerClickAction: .showDetail,
            openDelay: 0.15,
            closeDelay: 0.45)
    }
}

enum TokenTrackerEdgeRestingSurface: String, Codable, CaseIterable {
    case handle
    case providers
    case detail
}

enum TokenTrackerOpenAction: String, Codable, CaseIterable {
    case hover
    case click
    case none
}

enum TokenTrackerProviderClickAction: String, Codable, CaseIterable {
    case showDetail
    case togglePinnedDetail
    case openProviderSettings
}

enum TokenTrackerHorizontalEdge: String, Codable, CaseIterable {
    case left
    case right
}

enum TokenTrackerDockCompanionSide: String, Codable, CaseIterable {
    case leading
    case trailing
}

enum TokenTrackerBottomFallback: String, Codable, CaseIterable {
    case screenCorner
    case aboveDock
}

enum TokenTrackerSurfaceSize: String, Codable, CaseIterable {
    case compact
    case standard
    case wide
}

enum TokenTrackerDefaultProviders {
    /// Provider-specific by design: the canonical product brief defines these three launch defaults.
    static let candidates: [ProviderInstanceID] = [.codex, .claude, .deepseek]

    static func resolve(in availableProviderIDs: [ProviderInstanceID]) -> [ProviderInstanceID] {
        let available = Set(availableProviderIDs)
        return self.candidates.filter { available.contains($0) }
    }
}
