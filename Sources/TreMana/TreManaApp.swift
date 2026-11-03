import SwiftUI

@main
struct TreManaApp: App {
    @State private var model = TreManaModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1050, height: 690)

        Settings {
            Text("Configure your Transmission server in the main window.")
                .padding(28)
        }
    }
}
