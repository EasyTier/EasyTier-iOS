import SwiftUI

let APP_GROUP_ID: String = "group.site.yinmo.easytier"
let LOG_FILENAME: String = "easytier.log"

struct LogView: View {
    @StateObject private var tailer = LogTailer()
    @Namespace private var bottomID
    
    var body: some View {
        NavigationView {
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
            .navigationTitle("Logs")
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
            tailer.startWatching(appGroupID: APP_GROUP_ID, filename: LOG_FILENAME, fromStart: true)
        }
        .onDisappear {
            tailer.stop()
        }
        .alert(item: Binding<String?>(
            get: { tailer.errorMessage },
            set: { tailer.errorMessage = $0 }
        )) { msg in
            Alert(title: Text("Error"), message: Text(msg))
        }
    }
}

// Helper for Alert binding
extension String: @retroactive Identifiable {
    public var id: String { self }
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
