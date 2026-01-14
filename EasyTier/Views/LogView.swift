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
    @State private var exportURL: URL?
    @State private var isExportPresented = false
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
                        .onChange(of: tailer.logContent, initial: false) { _, _ in
                            // Auto-scroll to bottom on update
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
            }
            .navigationTitle("logging")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        tailer.logContent = []
                    }) {
                        Image(systemName: "trash")
                    }.tint(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        presentExport()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
        .onChange(of: scenePhase) { _, newPhase in
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
        .sheet(isPresented: $isExportPresented) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
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
        exportURL = url
        isExportPresented = true
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
            .onAppear {
                // Start a timer to write logs automatically
                Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    writeSimulatedLog()
                }
            }
    }

    // Helper function to write to the file
    static func writeSimulatedLog() {
        // Must match the ID and Filename above
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)?
            .appendingPathComponent(LOG_FILENAME) else { return }

        let message = "Preview Event: \(Date().formatted(date: .omitted, time: .standard))\n"

        // Simple append logic
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let offset = try? handle.offset(), offset > 1000 {
                try? handle.truncate(atOffset: 0)
            }
            handle.write(message.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? message.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
