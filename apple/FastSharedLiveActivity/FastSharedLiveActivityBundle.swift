import SwiftUI
import WidgetKit

@main
struct FastSharedLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        FastSharedUploadLiveActivity()
        FastSharedBundleUploadLiveActivity()
    }
}
