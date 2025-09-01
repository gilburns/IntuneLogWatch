//
//  IntuneLogWatchApp.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Sparkle

@main
struct IntuneLogWatchApp: App {
    private let updaterController: SPUStandardUpdaterController
    @State private var showingCertificateInspector = false
    
    init() {
        // Set up Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func collectAndExportLogs() {
        Task {
            await performLogCollection()
        }
    }
    
    
    private func openCLITool(withArgs arguments: [String] = []) {
        guard let cliPath = Bundle.main.path(forAuxiliaryExecutable: "intunelogwatch-cli") else {
            showAlert(title: "CLI Tool Not Found", message: "The CLI tool could not be located in the app bundle.")
            return
        }
        
        // Create a temporary script that runs the CLI tool and keeps the shell open
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("run_intune_cli.sh")
        
        let scriptContent = """
        #!/bin/bash
        echo "Running IntuneLogWatch CLI Tool..."
        echo "=================================="
        "\(cliPath)" \(arguments.joined(separator: " ")) "$@"
        echo ""
        echo "Type 'exit' to close this terminal session."
        exec "$SHELL"
        """
        
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Make the script executable
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+x", scriptPath.path]
            try process.run()
            process.waitUntilExit()
            
            // Open Terminal with the script
            openTerminal(at: scriptPath)
            
        } catch {
            showAlert(title: "Error", message: "Could not create temporary script: \(error.localizedDescription)")
        }
    }
    
    
   private func openTerminal(at url: URL?){
        guard let url = url,
              let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        
        NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: NSWorkspace.OpenConfiguration() )
    }

    
    @MainActor
    private func performLogCollection() async {
        let intuneLogsPath = "/Library/Logs/Microsoft/Intune/"
        let fileManager = FileManager.default
        
        // Check if the Intune logs directory exists
        guard fileManager.fileExists(atPath: intuneLogsPath) else {
            showAlert(title: "Logs Directory Not Found", 
                     message: "The Intune logs directory does not exist at \(intuneLogsPath)")
            return
        }
        
        do {
            // Get all log files
            let logFiles = try fileManager.contentsOfDirectory(atPath: intuneLogsPath)
                .filter { $0.hasSuffix(".log") }
                .map { intuneLogsPath + $0 }
            
            guard !logFiles.isEmpty else {
                showAlert(title: "No Log Files Found", 
                         message: "No log files were found in the Intune logs directory.")
                return
            }
            
            // Collect and sort all log entries
            let sortedLogEntries = await collectAndSortLogEntries(from: logFiles)
            
            // Create combined log content
            let combinedLogContent = createCombinedLogContent(from: sortedLogEntries)
            
            // Create temporary files
            let tempDir = fileManager.temporaryDirectory
            let combinedLogFile = tempDir.appendingPathComponent("IntuneLogWatch_Combined_Logs.log")
            let zipFile = tempDir.appendingPathComponent("IntuneLogWatch_Logs_\(getCurrentTimestamp()).zip")
            
            // Write combined log to file
            try combinedLogContent.write(to: combinedLogFile, atomically: true, encoding: .utf8)
            
            // Create zip file
            try await createZipFile(sourceFile: combinedLogFile, destinationFile: zipFile)
            
            // Present save dialog
            presentSaveDialog(for: zipFile)
            
        } catch {
            showAlert(title: "Error Collecting Logs", 
                     message: "An error occurred while collecting logs: \(error.localizedDescription)")
        }
    }
    
    private func collectAndSortLogEntries(from logFiles: [String]) async -> [(timestamp: Date, line: String)] {
        var allEntries: [(timestamp: Date, line: String)] = []
        
        for logFile in logFiles {
            do {
                let content = try String(contentsOfFile: logFile, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                for line in lines {
                    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    
                    if let timestamp = extractTimestamp(from: line) {
                        allEntries.append((timestamp: timestamp, line: line))
                    } else {
                        // If no timestamp, append to previous entry or use file modification date
                        let fallbackDate = getFileModificationDate(logFile) ?? Date()
                        allEntries.append((timestamp: fallbackDate, line: line))
                    }
                }
            } catch {
                // If we can't read a file, add a note about it
                let errorLine = "ERROR: Could not read log file \(logFile): \(error.localizedDescription)"
                allEntries.append((timestamp: Date(), line: errorLine))
            }
        }
        
        // Sort chronologically
        return allEntries.sorted { $0.timestamp < $1.timestamp }
    }
    
    private func extractTimestamp(from line: String) -> Date? {
        // Enhanced timestamp extraction to handle multiple formats
        let patterns = [
            // 2024-08-12 14:30:15.123
            "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}",
            // 2024-08-12 14:30:15
            "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
            // Aug 12 14:30:15
            "[A-Za-z]{3} \\d{1,2} \\d{2}:\\d{2}:\\d{2}"
        ]
        
        let formatters = [
            createDateFormatter(format: "yyyy-MM-dd HH:mm:ss.SSS"),
            createDateFormatter(format: "yyyy-MM-dd HH:mm:ss"),
            createDateFormatter(format: "MMM d HH:mm:ss")
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let range = line.range(of: pattern, options: .regularExpression),
               let date = formatters[index].date(from: String(line[range])) {
                return date
            }
        }
        
        return nil
    }
    
    private func createDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if format.contains("MMM") {
            // For formats like "Aug 12", assume current year
            formatter.defaultDate = Date()
        }
        return formatter
    }
    
    private func getFileModificationDate(_ filePath: String) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
    
    private func createCombinedLogContent(from entries: [(timestamp: Date, line: String)]) -> String {
        let header = """
        ================================================================================
        IntuneLogWatch Combined Log Collection
        Generated: \(getCurrentTimestamp())
        Total Entries: \(entries.count)
        ================================================================================
        
        """
        
        let logContent = entries.map { $0.line }.joined(separator: "\n")
        return header + logContent
    }
    
    private func createZipFile(sourceFile: URL, destinationFile: URL) async throws {
        // Use the system zip command for reliable compression
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = [
            "-j", // junk paths (don't include directory structure)
            destinationFile.path,
            sourceFile.path
        ]
        
        // Change to the directory containing the source file
        process.currentDirectoryURL = sourceFile.deletingLastPathComponent()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ZipError", code: Int(process.terminationStatus), 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create zip file"])
        }
    }
    
    private func getCurrentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
    
    private func presentSaveDialog(for zipFile: URL) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Collected Intune Logs"
        savePanel.nameFieldStringValue = zipFile.lastPathComponent
        savePanel.allowedContentTypes = [.zip]
        savePanel.canCreateDirectories = true
        
        savePanel.begin { result in
            if result == .OK, let destinationURL = savePanel.url {
                do {
                    // Remove existing file if it exists
                    try? FileManager.default.removeItem(at: destinationURL)
                    
                    // Copy the zip file to the chosen location
                    try FileManager.default.copyItem(at: zipFile, to: destinationURL)
                    
                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: zipFile)
                    
//                    self.showAlert(title: "Logs Collected Successfully", 
//                                 message: "Intune logs have been collected and saved to:\n\(destinationURL.path)")
                } catch {
                    self.showAlert(title: "Error Saving File", 
                                 message: "Could not save the log file: \(error.localizedDescription)")
                }
            } else {
                // Clean up temporary file when user cancels
                try? FileManager.default.removeItem(at: zipFile)
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(showingCertificateInspector: $showingCertificateInspector)
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            CommandGroup(after: .appInfo) {
                
                Divider()
                
                Button("Check for Updates...") {
                    updaterController.checkForUpdates(nil)
                }
            }
            
            CommandGroup(after: .newItem) {
                Button("Open Log File...") {
                    // Post notification to trigger file picker
                    NotificationCenter.default.post(name: .openLogFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()

                Button("Reload Local Logs") {
                    // Post notification to trigger local logs reload
                    NotificationCenter.default.post(name: .reloadLocalLogs, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("IntuneLogWatch Wiki…") {
                    openURL("https://github.com/gilburns/IntuneLogWatch/wiki")
                }

                Button("Intune Logs Folder…") {
                    openURL("file:/Library/Logs/Microsoft/Intune")
                }

                Divider()
                
                Button("Collect Logs…") {
                    collectAndExportLogs()
                }
                
                Button("Inspect MDM Certificate…") {
                    showingCertificateInspector = true
                }

                if #available(macOS 15.0, *) {
                    Button("Inspect MDM Certificate with CLI…") {
                        openCLITool(withArgs: [])
                    }.modifierKeyAlternate(.option) {
                        Button("Open MDM CLI…") {
                            openCLITool(withArgs: ["--help"])
                        }
                    }
                } else {
                    Button("Inspect MDM Certificate with CLI…") {
                        openCLITool(withArgs: [])
                    }
                }

                Divider()
                
                Button("Microsoft Graph Explorer…") {
                    openURL("https://developer.microsoft.com/en-us/graph/graph-explorer")
                }
            }
        }
    }
}

extension Notification.Name {
    static let openLogFile = Notification.Name("openLogFile")
    static let reloadLocalLogs = Notification.Name("reloadLocalLogs")
}

extension UTType {
    static var log: UTType {
        UTType(filenameExtension: "log") ?? UTType.plainText
    }
}
