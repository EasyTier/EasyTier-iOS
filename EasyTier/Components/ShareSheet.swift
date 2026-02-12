import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ShareSheet: View {
    let activityItems: [Any]
    var applicationActivities: [Any]? = nil

    var body: some View {
#if os(iOS)
        ShareActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities as? [UIActivity]
        )
#else
        EmptyView()
#endif
    }
}

#if os(iOS)
private struct ShareActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

@MainActor
func saveExportedFileToDisk(_ sourceURL: URL, suggestedName: String? = nil) throws {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = suggestedName ?? sourceURL.lastPathComponent

    guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
}
#endif
