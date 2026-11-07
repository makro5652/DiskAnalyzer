import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    LocationRow(model: model, location: model.homeLocation)
                    sectionTitle("Speicher")
                    ForEach(model.volumeLocations()) { LocationRow(model: model, location: $0) }
                    sectionTitle("Ordner")
                    ForEach(model.standardFolders()) { LocationRow(model: model, location: $0) }
                    ForEach(model.customLocations()) { LocationRow(model: model, location: $0, removable: true) }
                    chooseButton.padding(.top, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            cleanButton
        }
        .frame(width: 212)
        .modifier(PanelBackground(fill: AnyShapeStyle(
            LinearGradient(colors: [Theme.sidebarTop, Theme.sidebarBottom], startPoint: .top, endPoint: .bottom))))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Spacer()
            CircleIconButton(symbol: "sidebar.left", help: "Seitenleiste ausblenden") {
                model.sidebarVisible = false
            }
            HistoryMenu(model: model)
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(WindowDragArea())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private var chooseButton: some View {
        Button { model.chooseFolder() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Ordner auswählen …")
                Spacer()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.sidebarSelectionBorder.opacity(0.9)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cleanButton: some View {
        Button { model.showCleanSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14))
                Text("Mehr aufräumen")
                    .font(.system(size: 12.5))
                Spacer()
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 24)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.root == nil)
        .help("Aufräum-Vorschläge, Duplikate und Dateitypen")
    }
}

private struct LocationRow: View {
    let model: AppModel
    let location: SidebarLocation
    var removable = false
    @State private var hovering = false

    var body: some View {
        let path = location.url.path
        let active = model.lastURL?.path == path
        Button { model.show(location.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: location.symbol)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(location.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if active, model.isScanning {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16)
                } else if model.scans[path] != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.sidebarSelection)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.sidebarSelectionBorder)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.rowHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(path)
        .contextMenu {
            Button("Neu scannen") { model.scan(location.url) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([location.url]) }
            if removable {
                Divider()
                Button("Aus der Liste entfernen") { model.removeCustomFolder(path) }
            }
        }
    }
}

private struct HistoryMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            Button("Neu scannen") { model.rescan() }
                .disabled(model.lastURL == nil || model.isScanning)
            Divider()
            Button("Zurück") { model.goBack() }.disabled(!model.canGoBack)
            Button("Vor") { model.goForward() }.disabled(!model.canGoForward)
            Button("Eine Ebene hoch") { model.goUp() }.disabled(model.focus?.parent == nil)
            if !model.recents.isEmpty {
                Divider()
                Section("Zuletzt analysiert") {
                    ForEach(model.recents, id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.show(URL(fileURLWithPath: path))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Theme.text)
        .fixedSize()
        .frame(width: 34, height: 34)
        .background(Theme.circleButton, in: Circle())
        .overlay(Circle().strokeBorder(Theme.hairline).allowsHitTesting(false))
        .help("Verlauf und neu scannen")
    }
}
