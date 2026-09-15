import AppKit
import RatioCore
import UniformTypeIdentifiers

extension AppModel {
    var exportDatasetName: String { session.isDemo ? "Fictional demo" : "Real activity" }

    func exportActivityCSV() {
        refreshTracking()
        let isDemo = session.isDemo
        let csv = session.ledger.activityCSV()
        let panel = NSSavePanel()
        panel.title = "Export \(isDemo ? "Fictional Demo" : "Real Activity")"
        panel.message = isDemo
            ? "Save fictional demo activity from all demo days. Your real activity is separate."
            : "Save your retained daily activity and current categories as a local CSV file."
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ratio-\(isDemo ? "demo" : "activity")-\(today).csv"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "CSV could not be saved"
            alert.informativeText = "\(error.localizedDescription) Your activity remains available in Open Ratio."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func revealDataDirectory() {
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectory.path)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Data folder could not be opened"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
