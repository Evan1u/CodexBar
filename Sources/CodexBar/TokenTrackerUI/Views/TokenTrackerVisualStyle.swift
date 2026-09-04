import SwiftUI

struct TokenTrackerSurfaceVisualStyle {
    let contrast: ColorSchemeContrast

    var outlineOpacity: Double {
        self.contrast == .increased ? 0.42 : 0.10
    }

    var handleOutlineOpacity: Double {
        self.contrast == .increased ? 0.62 : 0.18
    }

    var inactiveTileOpacity: Double {
        self.contrast == .increased ? 0.16 : 0.055
    }

    var hoveredTileOpacity: Double {
        self.contrast == .increased ? 0.28 : 0.12
    }

    var dividerOpacity: Double {
        self.contrast == .increased ? 0.32 : 0.08
    }

}
