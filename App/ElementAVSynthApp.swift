import SwiftUI
#if canImport(ElementAVCore)
import ElementAVCore
#endif

@main
struct ElementAVSynthApp: App {
    var body: some Scene {
        WindowGroup {
            ElementSynthDashboardView()
        }
    }
}
