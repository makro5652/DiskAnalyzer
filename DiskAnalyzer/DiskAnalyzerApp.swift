import SwiftUI

@main
struct DiskAnalyzerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Speicher-Analyse", id: "main") {
            ContentView(model: model)
                .task {
                    // Start mit Argument: DiskAnalyzer --scan /Pfad
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
                        model.show(URL(fileURLWithPath: args[i + 1]))
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1500, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Ordner auswählen …") { model.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Neu scannen") { model.rescan() }
                    .keyboardShortcut("r")
                    .disabled(model.lastURL == nil || model.isScanning)
            }
            CommandGroup(after: .textEditing) {
                Button("Dateien suchen") { model.searchVisible = true }
                    .keyboardShortcut("f")
                Divider()
                Button("Auswahl entfernen …") { model.confirmAndDelete(model.selectedNodes, permanent: false) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selection.isEmpty)
                Button("Auswahl aufheben") { model.selection = [] }
                    .disabled(model.selection.isEmpty)
            }
            CommandMenu("Gehe zu") {
                Button("Zurück") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Button("Vor") { model.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canGoForward)
                Button("Eine Ebene hoch") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.focus?.parent == nil)
            }
            CommandGroup(replacing: .help) {
                Button("DiskAnalyzer-Hilfe") { model.showHelp = true }
            }
        }
    }
}
