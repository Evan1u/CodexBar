import CodexBarCore

enum TokenTrackerProviderSelection {
    static func resolve(
        savedID: String?,
        lastOpenedID: String?,
        visibleProviderIDs: [ProviderInstanceID],
        catalogProviderIDs: [ProviderInstanceID],
        configuredProviderIDs: Set<ProviderInstanceID>) -> ProviderInstanceID?
    {
        let catalog = Set(catalogProviderIDs)
        let visible = visibleProviderIDs.filter { catalog.contains($0) }
        let visibleSet = Set(visible)

        if let savedID = savedID.flatMap(ProviderInstanceID.init(rawValue:)), visibleSet.contains(savedID) {
            return savedID
        }
        if let lastOpenedID = lastOpenedID.flatMap(ProviderInstanceID.init(rawValue:)),
           visibleSet.contains(lastOpenedID)
        {
            return lastOpenedID
        }
        if let configured = visible.first(where: { configuredProviderIDs.contains($0) }) {
            return configured
        }
        return visible.first
    }
}
