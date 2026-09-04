import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct TokenTrackerSettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    let actions: TokenTrackerAppActions
    @State private var screenRevision = 0

    private var preferences: TokenTrackerPreferencesStore {
        self.settings.tokenTrackerPreferences
    }

    var body: some View {
        Form {
            Section {
                SettingsRowLabel(
                    "Presentation",
                    subtitle: "Token Tracker appears only as a movable Side rail.")
            } header: {
                Text("Token Tracker")
            }

            self.providerSection

            Section {
                TokenTrackerSideSettingsCard(
                    preferences: self.preferences,
                    providerOptions: self.providerOptions,
                    screens: self.screenOptions)
            } header: {
                Text("Side rail")
            } footer: {
                SettingsSectionFooter(
                    "Drag the rail to either screen edge; its screen, position, and interaction settings are retained.")
            }

            Section {
                Toggle("Start Token Tracker at login", isOn: self.$settings.launchAtLogin)

                LabeledContent("Open Token Tracker shortcut") {
                    TokenTrackerShortcutRecorder()
                }

                HStack {
                    SettingsRowLabel(
                        "Usage data",
                        subtitle: "Uses the original provider refresh and cache pipeline.")
                    Spacer()
                    Button(self.store.refreshingProviders.isEmpty ? "Refresh now" : "Refreshing…") {
                        self.actions.refresh()
                    }
                    .disabled(!self.store.refreshingProviders.isEmpty)
                }
            } header: {
                Text("Daily operation")
            } footer: {
                HStack {
                    Text("Provider Settings buttons above open the original CodexBar configuration pages.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Token Tracker") {
                        self.actions.quit()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollContentBackground(.hidden)
        .background(FocusResigningBackground())
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification))
        { _ in
            self.screenRevision &+= 1
        }
    }

    private var providerSection: some View {
        Section {
            if self.visibleCatalog.isEmpty {
                Text("No Providers are shown. Enable one below to populate Token Tracker surfaces.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(self.visibleCatalog) { provider in
                        TokenTrackerProviderSettingsRow(
                            provider: provider,
                            isVisible: self.visibilityBinding(for: provider.id),
                            openSettings: { self.actions.openProviderSettings(provider.id) })
                    }
                    .onMove { offsets, destination in
                        self.preferences.moveVisibleProviders(fromOffsets: offsets, toOffset: destination)
                    }
                }
                .frame(minHeight: 84, idealHeight: self.providerListHeight, maxHeight: 240)
                .accessibilityLabel("Visible Provider order")
            }

            DisclosureGroup("Available Providers") {
                ForEach(self.hiddenCatalog) { provider in
                    TokenTrackerProviderSettingsRow(
                        provider: provider,
                        isVisible: self.visibilityBinding(for: provider.id),
                        openSettings: { self.actions.openProviderSettings(provider.id) })
                }
            }
        } header: {
            Text("Providers")
        } footer: {
            SettingsSectionFooter(
                "Drag shown Providers to reorder them. Visibility here is independent "
                    + "from whether a Provider is enabled upstream.")
        }
    }
}

extension TokenTrackerSettingsView {
    private var catalog: [TokenTrackerProviderCatalogEntry] {
        _ = self.preferences.catalogRevision
        return TokenTrackerProviderProjection.liveCatalog()
    }

    private var visibleCatalog: [TokenTrackerProviderCatalogEntry] {
        let byID = Dictionary(uniqueKeysWithValues: self.catalog.map { ($0.id, $0) })
        return self.preferences.effectiveVisibleProviderIDs.compactMap { byID[$0] }
    }

    private var hiddenCatalog: [TokenTrackerProviderCatalogEntry] {
        let visible = Set(self.visibleCatalog.map(\.id))
        return self.catalog.filter { !visible.contains($0.id) }
    }

    private var providerOptions: [TokenTrackerProviderOption] {
        self.visibleCatalog.map { TokenTrackerProviderOption(id: $0.id, label: $0.displayName) }
    }

    private var providerListHeight: CGFloat {
        min(240, max(84, CGFloat(self.visibleCatalog.count) * 34 + 8))
    }

    private var screenOptions: [TokenTrackerScreenOption] {
        _ = self.screenRevision
        return TokenTrackerScreenOption.live()
    }

    private func visibilityBinding(for providerID: ProviderInstanceID) -> Binding<Bool> {
        Binding(
            get: { self.preferences.preferences.visibleProviderIDs.contains(providerID.rawValue) },
            set: { self.preferences.setVisible($0, providerID: providerID) })
    }
}

private struct TokenTrackerProviderSettingsRow: View {
    let provider: TokenTrackerProviderCatalogEntry
    @Binding var isVisible: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Toggle(self.provider.displayName, isOn: self.$isVisible)
            Spacer()
            Button("Provider Settings", action: self.openSettings)
                .buttonStyle(.link)
                .accessibilityLabel("Open \(self.provider.displayName) Provider Settings")
        }
    }
}

struct TokenTrackerProviderOption: Identifiable, Equatable {
    let id: ProviderInstanceID
    let label: String
}

struct TokenTrackerScreenOption: Identifiable, Equatable {
    let id: String
    let label: String

    @MainActor
    static func live() -> [Self] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = TokenTrackerScreenSnapshot(screen: screen).persistentID else { return nil }
            return Self(id: id, label: "\(screen.localizedName) · \(index + 1)")
        }
    }
}

@MainActor
private struct TokenTrackerSideSettingsCard: View {
    @Bindable var preferences: TokenTrackerPreferencesStore
    let providerOptions: [TokenTrackerProviderOption]
    let screens: [TokenTrackerScreenOption]

    var body: some View {
        GroupBox("Side") {
            VStack(spacing: 12) {
                TokenTrackerScreenPicker(
                    title: "Target screen",
                    selection: self.screenBinding,
                    screens: self.screens)
                SettingsMenuPicker(selection: self.edgeBinding, options: TokenTrackerHorizontalEdge.allCases) {
                    SettingsRowLabel("Screen edge")
                } optionLabel: { Text($0.label) }
                TokenTrackerPercentageSlider(title: "Vertical position", value: self.normalizedYBinding)
                SettingsMenuPicker(selection: self.surfaceBinding, options: TokenTrackerEdgeRestingSurface.allCases) {
                    SettingsRowLabel("Default surface")
                } optionLabel: { Text($0.label) }
                TokenTrackerProviderPicker(
                    title: "Default Provider",
                    selection: self.defaultProviderBinding,
                    options: self.providerOptions)
                TokenTrackerProviderPicker(
                    title: "Last opened Provider",
                    selection: self.lastProviderBinding,
                    options: self.providerOptions)
                TokenTrackerBehaviorRows(
                    openAction: self.openActionBinding,
                    clickAction: self.clickActionBinding,
                    openDelay: self.openDelayBinding,
                    closeDelay: self.closeDelayBinding)
                SettingsMenuPicker(selection: self.sizeBinding, options: TokenTrackerSurfaceSize.allCases) {
                    SettingsRowLabel("Rail size")
                } optionLabel: { Text($0.label) }
            }
            .padding(.top, 6)
        }
    }

    private var interaction: TokenTrackerEdgeInteractionPreferences {
        self.preferences.preferences.side.interaction
    }

    private var screenBinding: Binding<String?> {
        Binding(
            get: { self.preferences.preferences.side.screenID },
            set: { value in self.preferences.update { $0.side.screenID = value } })
    }

    private var edgeBinding: Binding<TokenTrackerHorizontalEdge> {
        Binding(
            get: { self.preferences.preferences.side.edge },
            set: { value in self.preferences.update { $0.side.edge = value } })
    }

    private var normalizedYBinding: Binding<Double> {
        Binding(
            get: { self.preferences.preferences.side.normalizedY },
            set: { value in self.preferences.update { $0.side.normalizedY = value } })
    }

    private var surfaceBinding: Binding<TokenTrackerEdgeRestingSurface> {
        self.interactionBinding(\.restingSurface)
    }

    private var defaultProviderBinding: Binding<ProviderInstanceID?> {
        self.providerBinding(\.persistentProviderID)
    }

    private var lastProviderBinding: Binding<ProviderInstanceID?> {
        self.providerBinding(\.lastOpenedProviderID)
    }

    private var openActionBinding: Binding<TokenTrackerOpenAction> {
        self.interactionBinding(\.openAction)
    }

    private var clickActionBinding: Binding<TokenTrackerProviderClickAction> {
        self.interactionBinding(\.providerClickAction)
    }

    private var openDelayBinding: Binding<TimeInterval> {
        self.interactionBinding(\.openDelay)
    }

    private var closeDelayBinding: Binding<TimeInterval> {
        self.interactionBinding(\.closeDelay)
    }

    private var sizeBinding: Binding<TokenTrackerSurfaceSize> {
        Binding(
            get: { self.preferences.preferences.side.railSize },
            set: { value in self.preferences.update { $0.side.railSize = value } })
    }

    private func interactionBinding<Value>(
        _ keyPath: WritableKeyPath<TokenTrackerEdgeInteractionPreferences, Value>) -> Binding<Value>
    {
        Binding(
            get: { self.interaction[keyPath: keyPath] },
            set: { value in self.preferences.update { $0.side.interaction[keyPath: keyPath] = value } })
    }

    private func providerBinding(
        _ keyPath: WritableKeyPath<TokenTrackerEdgeInteractionPreferences, String?>)
        -> Binding<ProviderInstanceID?>
    {
        Binding(
            get: { self.interaction[keyPath: keyPath].flatMap(ProviderInstanceID.init(rawValue:)) },
            set: { value in
                self.preferences.update { $0.side.interaction[keyPath: keyPath] = value?.rawValue }
            })
    }
}

private struct TokenTrackerBehaviorRows: View {
    @Binding var openAction: TokenTrackerOpenAction
    @Binding var clickAction: TokenTrackerProviderClickAction
    @Binding var openDelay: TimeInterval
    @Binding var closeDelay: TimeInterval

    private let delays: [TimeInterval] = [0, 0.1, 0.15, 0.25, 0.45, 0.75, 1]

    var body: some View {
        SettingsMenuPicker(selection: self.$openAction, options: TokenTrackerOpenAction.allCases) {
            SettingsRowLabel("Open behavior")
        } optionLabel: { Text($0.label) }
        SettingsMenuPicker(selection: self.$clickAction, options: TokenTrackerProviderClickAction.allCases) {
            SettingsRowLabel("Provider click")
        } optionLabel: { Text($0.label) }
        SettingsMenuPicker(selection: self.$openDelay, options: self.delays) {
            SettingsRowLabel("Open delay")
        } optionLabel: { Text($0.delayLabel) }
        SettingsMenuPicker(selection: self.$closeDelay, options: self.delays) {
            SettingsRowLabel("Close delay")
        } optionLabel: { Text($0.delayLabel) }
    }
}

private struct TokenTrackerProviderPicker: View {
    let title: String
    @Binding var selection: ProviderInstanceID?
    let options: [TokenTrackerProviderOption]

    var body: some View {
        SettingsMenuPicker(selection: self.$selection, options: [nil] + self.options.map { Optional($0.id) }) {
            SettingsRowLabel(self.title)
        } optionLabel: { providerID in
            Text(self.options.first(where: { $0.id == providerID })?.label ?? "Automatic")
        }
    }
}

private struct TokenTrackerScreenPicker: View {
    let title: String
    @Binding var selection: String?
    let screens: [TokenTrackerScreenOption]

    var body: some View {
        SettingsMenuPicker(selection: self.$selection, options: [nil] + self.screens.map { Optional($0.id) }) {
            SettingsRowLabel(self.title)
        } optionLabel: { screenID in
            Text(self.screens.first(where: { $0.id == screenID })?.label ?? "Automatic")
        }
    }
}

private struct TokenTrackerPercentageSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            SettingsRowLabel(self.title)
            Slider(value: self.$value, in: 0...1)
                .accessibilityLabel(self.title)
            Text("\(Int(self.value * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

extension TokenTrackerPresentationMode {
    fileprivate var label: String {
        switch self {
        case .notch: "Notch"
        case .side: "Side"
        case .bottom: "Bottom"
        case .menuBarOnly: "Menu Bar Only"
        }
    }
}

extension TokenTrackerNotchRestingSurface {
    fileprivate var label: String {
        switch self {
        case .defaultProvider: "Default Provider"
        case .providers: "Provider Overview"
        case .detail: "Provider Detail"
        }
    }
}

extension TokenTrackerEdgeRestingSurface {
    fileprivate var label: String {
        switch self {
        case .handle: "Handle"
        case .providers: "Providers"
        case .detail: "Provider Detail"
        }
    }
}

extension TokenTrackerOpenAction {
    fileprivate var label: String {
        switch self {
        case .hover: "Hover or Click"
        case .click: "Click"
        case .none: "Shortcut or Persistent Only"
        }
    }
}

extension TokenTrackerProviderClickAction {
    fileprivate var label: String {
        switch self {
        case .showDetail: "Show Detail"
        case .togglePinnedDetail: "Toggle Pinned Detail"
        case .openProviderSettings: "Open Provider Settings"
        }
    }
}

extension TokenTrackerHorizontalEdge {
    fileprivate var label: String {
        self == .left ? "Left" : "Right"
    }
}

extension TokenTrackerDockCompanionSide {
    fileprivate var label: String {
        self == .leading ? "Leading" : "Trailing"
    }
}

extension TokenTrackerBottomFallback {
    fileprivate var label: String {
        self == .aboveDock ? "Above Dock" : "Screen Corner"
    }
}

extension TokenTrackerSurfaceSize {
    fileprivate var label: String {
        self.rawValue.capitalized
    }
}

extension TimeInterval {
    fileprivate var delayLabel: String {
        self == 0 ? "Immediate" : String(format: "%.2f s", self)
    }
}
