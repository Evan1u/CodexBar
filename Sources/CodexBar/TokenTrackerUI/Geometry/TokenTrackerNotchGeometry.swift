import AppKit
import ColorSync

struct TokenTrackerScreenSnapshot: Equatable, Sendable {
    let runtimeDisplayID: CGDirectDisplayID?
    let persistentID: String?
    let isBuiltIn: Bool
    let frame: CGRect
    let visibleFrame: CGRect
    let safeTopInset: CGFloat
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?

    init(
        runtimeDisplayID: CGDirectDisplayID? = nil,
        persistentID: String? = nil,
        isBuiltIn: Bool = false,
        frame: CGRect,
        visibleFrame: CGRect,
        safeTopInset: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil)
    {
        self.runtimeDisplayID = runtimeDisplayID
        self.persistentID = persistentID
        self.isBuiltIn = isBuiltIn
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeTopInset = safeTopInset
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea.flatMap { $0.isEmpty ? nil : $0 }
        self.auxiliaryTopRightArea = auxiliaryTopRightArea.flatMap { $0.isEmpty ? nil : $0 }
    }

    @MainActor
    init(screen: NSScreen) {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
        let persistentID: String? = displayID.flatMap { displayID in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String
        }
        self.init(
            runtimeDisplayID: displayID,
            persistentID: persistentID,
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea)
    }
}

enum TokenTrackerScreenResolver {
    static func resolve(
        screens: [TokenTrackerScreenSnapshot],
        savedPersistentID: String?,
        sessionPreferredDisplayID: CGDirectDisplayID? = nil,
        mouseLocation: CGPoint?,
        mainDisplayID: CGDirectDisplayID?) -> TokenTrackerScreenSnapshot?
    {
        if let savedPersistentID,
           let saved = screens.first(where: { $0.persistentID == savedPersistentID })
        {
            return saved
        }
        if let sessionPreferredDisplayID,
           let session = screens.first(where: { $0.runtimeDisplayID == sessionPreferredDisplayID })
        {
            return session
        }
        if let builtInNotch = screens.first(where: { $0.isBuiltIn && $0.safeTopInset > 0 }) {
            return builtInNotch
        }
        if let mouseLocation,
           let mouseScreen = screens.first(where: { $0.frame.contains(mouseLocation) })
        {
            return mouseScreen
        }
        if let mainDisplayID,
           let main = screens.first(where: { $0.runtimeDisplayID == mainDisplayID })
        {
            return main
        }
        return screens.first
    }
}

enum TokenTrackerNotchGeometry {
    static func centerX(on screen: TokenTrackerScreenSnapshot) -> CGFloat {
        guard screen.safeTopInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX
        else { return screen.frame.midX }
        return (left.maxX + right.minX) / 2
    }

    static func obstructionWidth(on screen: TokenTrackerScreenSnapshot) -> CGFloat? {
        guard screen.safeTopInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX
        else { return nil }
        return right.minX - left.maxX
    }

    static func compactSize(on screen: TokenTrackerScreenSnapshot) -> CGSize {
        CGSize(
            width: max((self.obstructionWidth(on: screen) ?? 174) + 16, 190),
            height: max(screen.safeTopInset, 38))
    }

    static func frame(size requestedSize: CGSize, on screen: TokenTrackerScreenSnapshot) -> CGRect {
        let width = min(max(requestedSize.width, 0), max(screen.visibleFrame.width, 0))
        let height = min(max(requestedSize.height, 0), max(screen.visibleFrame.height, 0))
        let desiredX = self.centerX(on: screen) - width / 2
        let maximumX = max(screen.visibleFrame.minX, screen.visibleFrame.maxX - width)
        let x = min(max(desiredX, screen.visibleFrame.minX), maximumX)
        let y = max(screen.visibleFrame.minY, screen.frame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
