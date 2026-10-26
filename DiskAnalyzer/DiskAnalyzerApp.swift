import SwiftUI

@main
struct DiskAnalyzerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Speicher-Analyse") {
            ContentView(model: model)
                .task {
                    // Start mit Argument: DiskAnalyzer --scan /Pfad
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
                        model.scan(URL(fileURLWithPath: args[i + 1]))
                    }
                }
        }
        .defaultSize(width: 1280, height: 760)
    }
}
