import SwiftUI
import EasyTierShared

private func logFileURL() -> URL? {
    FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)?
        .appendingPathComponent(LOG_FILENAME)
}

struct LogView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tailer = LogTailer()
    @Namespace private var bottomID
    @State private var wasWatchingBeforeBackground = false
#if os(iOS)
    @State private var exportURL: URL?
    @State private var isExportPresented = false
#endif
    @State private var exportErrorMessage: TextItem?
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                // Log Content
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading) {
                            ForEach(tailer.logContent) { line in
                                Text(line.text)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            Text("").id(bottomID)
                        }
                        .padding()
                        .onChange(of: tailer.logContent) { _ in
                            // Auto-scroll to bottom on update
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
                    }
                }
#if os(iOS)
                .background(Color(UIColor.systemGroupedBackground))
#endif
            }
            .navigationTitle("logging")
            .adaptiveNavigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: ToolbarLeading) {
                    Button(action: {
                        tailer.logContent = []
                    }) {
                        Image(systemName: "trash")
                    }.tint(.red)
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        presentExport()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: ToolbarTrailing) {
                    Button(action: {
                        if tailer.isWatching {
                            tailer.stop()
                        } else {
                            tailer.startWatching(appGroupID: APP_GROUP_ID, filename: LOG_FILENAME, fromStart: false)
                        }
                    }) {
                        Image(systemName: tailer.isWatching ? "pause" : "play")
                    }
                }
            }
        }
        .onAppear {
            if !tailer.isWatching {
                tailer.startWatching(appGroupID: APP_GROUP_ID, filename: LOG_FILENAME, fromStart: true)
            }
        }
        .onDisappear {
            tailer.stop()
            wasWatchingBeforeBackground = false
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if wasWatchingBeforeBackground {
                    tailer.startWatching(appGroupID: APP_GROUP_ID, filename: LOG_FILENAME, fromStart: false)
                    wasWatchingBeforeBackground = false
                }
            case .inactive, .background:
                wasWatchingBeforeBackground = tailer.isWatching
                tailer.stop()
            @unknown default:
                break
            }
        }
        .alert(item: $tailer.errorMessage) { msg in
            Alert(title: Text("common.error"), message: Text(msg.text))
        }
        .alert(item: $exportErrorMessage) { msg in
            Alert(title: Text("common.error"), message: Text(msg.text))
        }
#if os(iOS)
        .sheet(isPresented: $isExportPresented) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
#endif
    }

    private func presentExport() {
        guard let url = logFileURL() else {
            exportErrorMessage = .init("Log file not found.")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            exportErrorMessage = .init("Log file not found.")
            return
        }
#if os(iOS)
        exportURL = url
        isExportPresented = true
#elseif os(macOS)
        do {
            try saveExportedFileToDisk(url)
        } catch {
            exportErrorMessage = .init(error.localizedDescription)
        }
#endif
    }
}

#if DEBUG
#Preview("Log") {
    LogView()
}
#endif
