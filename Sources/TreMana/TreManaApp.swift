import SwiftUI
import TreManaCore

@main
struct TreManaApp: App {
    @State private var model = TreManaModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 840, minHeight: 560)
        }
        .defaultSize(width: 1140, height: 740)

        Settings {
            Text("Configure your Transmission server in the main window.")
                .padding(28)
        }
    }
}
