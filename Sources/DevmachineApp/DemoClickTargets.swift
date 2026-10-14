import SwiftUI

/// Where the controls the site walk clicks sit, so it can draw the pointer
/// moving to them: a bitmap capture has no pointer of its own. Recorded only
/// while a demo walk captures; any other launch leaves the views untouched.
@MainActor
enum DemoClickTargets {
    static let isRecording = DemoSnapshots.targetDirectory != nil

    /// Frames in their own window's points, from the top-left corner.
    static var frames: [String: CGRect] = [:]
}

extension View {
    @ViewBuilder
    func demoClickTarget(_ id: String) -> some View {
        if DemoClickTargets.isRecording {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { DemoClickTargets.frames[id] = frame }
            }
        } else {
            self
        }
    }
}
