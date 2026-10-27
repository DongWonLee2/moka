import MokaCore
import SwiftUI

@main
struct MokaApp: App {
    var body: some Scene {
        MenuBarExtra("Moka", systemImage: "timer") {
            Text("MokaCore: \(Health.check())")
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
    }
}
