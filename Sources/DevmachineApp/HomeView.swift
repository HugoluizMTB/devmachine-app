import SwiftUI
import AppKit
import DevmachineCore

/// Home: the canvas of widgets described by `<config>/boards/home.yml`.
struct HomeView: View {
    @ObservedObject private var controller = HomeBoardController.shared

    static func macName(demo: Bool = DemoMode.isActive) -> String {
        demo ? DemoData.macName : (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    var body: some View {
        HomeCanvasView(controller: controller)
    }
}
