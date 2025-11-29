//
//  IntuneLogWatchApp.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Sparkle

enum AppearancePreference: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct IntuneLogWatchApp: App {
    private let updaterController: SPUStandardUpdaterController
    @State private var showingCertificateInspector = false
    @State private var errorCodesWindowController: ErrorCodesReferenceWindowControllerSimple?
    @State private var sidebarVisibility = NavigationSplitViewVisibility.automatic
    @State private var enrollmentExpanded: Bool = false
    @State private var networkExpanded: Bool = false
    @State private var analysisExpanded: Bool = true
    @AppStorage("appearancePreference") private var appearancePreference: AppearancePreference = .system
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Set up Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            return true
        }
        
        func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
            return true
        }
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openClipLibraryWindow() {
        // Post notification to open clip library
        NotificationCenter.default.post(name: .openClipLibrary, object: nil)
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
        echo "You can run the CLI tool from here:" 
        echo "\(cliPath)"
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

    private func showErrorCodesReference() {
        if let windowController = errorCodesWindowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
        } else {
            let windowController = ErrorCodesReferenceWindowControllerSimple()
            windowController.showWindow(nil)
            self.errorCodesWindowController = windowController
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                showingCertificateInspector: $showingCertificateInspector,
                sidebarVisibility: $sidebarVisibility,
                enrollmentExpanded: $enrollmentExpanded,
                networkExpanded: $networkExpanded,
                analysisExpanded: $analysisExpanded
            )
            .preferredColorScheme(appearancePreference.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: .showErrorCodesReference)) { _ in
                showErrorCodesReference()
            }
        }
        .windowStyle(DefaultWindowStyle())

        WindowGroup("Clip Library", id: "clip-library") {
            ClipLibraryWindowWrapper()
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 600)

        .commands {
            CommandGroup(after: .appInfo) {
                
                Divider()
                
                Button(action: {
                    updaterController.checkForUpdates(nil)
                }) {
                    Label("Check for Updates…", systemImage: "arrow.down.circle")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(action: {
                    NSApp.sendAction(
                        #selector(NSWindowController().newWindowForTab(_:)),
                        to: nil,
                        from: nil
                    )
                }) {
                    Label("New Window", systemImage: "macwindow.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(action: {
                    if let currentWindow = NSApp.keyWindow,
                      let windowController = currentWindow.windowController {
                      windowController.newWindowForTab(nil)
                      if let newWindow = NSApp.keyWindow,
                        currentWindow != newWindow {
                          currentWindow.addTabbedWindow(newWindow, ordered: .above)
                        }
                    }
                }) {
                    Label("New Tab", systemImage: "macwindow.stack")
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button(action: {
                    // Post notification to trigger file picker
                    NotificationCenter.default.post(name: .openLogFile, object: nil)
                }) {
                    Label("Open Log File…", systemImage: "arrow.up.right")
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button(action: {
                    // Post notification to trigger local logs reload
                    NotificationCenter.default.post(name: .reloadLocalLogs, object: nil)
                }) {
                    Label("Reload Local Logs", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button(action: {
                    // Post notification to focus search field
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }) {
                    Label("Search Policies…", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

            }
            
            CommandGroup(after: .toolbar) {
                Divider()
                
                Button(action: {
                    NSApp.sendAction(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        to: nil,
                        from: nil
                    )
                }) {
                    Label(sidebarVisibility == .doubleColumn ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Divider()
            }
            
            CommandGroup(after: CommandGroupPlacement.toolbar) {

                Divider()

                Button(action: {
                    enrollmentExpanded.toggle()
                }) {
                    Label(enrollmentExpanded ? "Collapse Enrollment Status" : "Expand Enrollment Status",
                          systemImage: "person.text.rectangle")
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(sidebarVisibility == .doubleColumn)

                Button(action: {
                    networkExpanded.toggle()
                }) {
                    Label(networkExpanded ? "Collapse Network Connectivity" : "Expand Network Connectivity",
                          systemImage: "network")
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(sidebarVisibility == .doubleColumn)

                Button(action: {
                    analysisExpanded.toggle()
                }) {
                    Label(analysisExpanded ? "Collapse Analysis Summary" : "Expand Analysis Summary",
                          systemImage: "chart.bar.doc.horizontal")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(sidebarVisibility == .doubleColumn)

                Divider()
                
                Button(action: {
                    // Post notification to show all log entries
                    NotificationCenter.default.post(name: .showAllLogEntries, object: nil)
                }) {
                    Label("View All Log Entries…", systemImage: "text.page.badge.magnifyingglass")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button(action: {
                    openClipLibraryWindow()
                }) {
                    Label("Clip Library", systemImage: "scissors")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Menu {
                    ForEach(AppearancePreference.allCases, id: \.self) { preference in
                        Button(action: {
                            if preference == .system {
                                // Workaround: First switch to matching light/dark mode, then to system
                                let currentSystemAppearance = NSApp.effectiveAppearance.name
                                let isDark = currentSystemAppearance == .darkAqua || currentSystemAppearance == .vibrantDark

                                // First set to the matching mode
                                appearancePreference = isDark ? .dark : .light

                                // Then immediately switch to system
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    appearancePreference = .system
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                                    appearancePreference = .system
                                }
                            } else {
                                appearancePreference = preference
                            }
                        } ) {
                            HStack {
                                Text(preference.displayName)
                                if appearancePreference == preference {
                                    Image(systemName: "checkmark")
                                }
                            } 
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                Divider()

            }

            CommandGroup(replacing: .help) {
                Button(action: {
                    openURL("https://github.com/gilburns/IntuneLogWatch/wiki")
                }) {
                    Label("IntuneLogWatch Wiki…", systemImage: "document")
                }

                Button(action: {
                    openURL("https://github.com/gilburns/IntuneLogWatch/releases")
                }) {
                    Label("IntuneLogWatch Release Notes…", systemImage: "document")
                }

                Divider()

                Button(action: {
                    showErrorCodesReference()
                }) {
                    Label("Intune Error Codes Reference…", systemImage: "exclamationmark.triangle")
                }

                Divider()

                Button(action: {
                    openURL("file:/Library/Logs/Microsoft/Intune")
                }) {
                    Label("Intune Logs Folder…", systemImage: "arrow.up.folder")
                }

                Button(action: {
                    collectAndExportLogs()
                }) {
                    Label("Collect Logs…", systemImage: "text.badge.plus")
                }

                Divider()

                Button(action: {
                    showingCertificateInspector = true
                }) {
                    Label("Inspect MDM Certificate…", systemImage: "text.page.badge.magnifyingglass")
                }


                if #available(macOS 15.0, *) {
                    Button(action: {
                        openCLITool(withArgs: [])
                    }) {
                        Label("Inspect MDM Certificate with CLI…", systemImage: "apple.terminal")
                    }
                    .modifierKeyAlternate(.option) {
                        Button(action: {
                            openCLITool(withArgs: ["--help"])
                        }) {
                            Label("Open MDM CLI…", systemImage: "apple.terminal")
                        }
                    }
                } else {
                    Button(action: {
                        openCLITool(withArgs: [])
                    }) {
                        Label("Inspect MDM Certificate with CLI…", systemImage: "apple.terminal")
                    }
                }

                Divider()
                
                Button(action: {
                    openURL("https://developer.microsoft.com/en-us/graph/graph-explorer")
                }) {
                    Label("Microsoft Graph Explorer…", systemImage: "curlybraces.square")
                }
            }
        }
    }
}

extension Notification.Name {
    static let openLogFile = Notification.Name("openLogFile")
    static let reloadLocalLogs = Notification.Name("reloadLocalLogs")
    static let focusSearchField = Notification.Name("focusSearchField")
    static let focusPolicyList = Notification.Name("focusPolicyList")
    static let focusSearchFieldDirect = Notification.Name("focusSearchFieldDirect")
    static let showAllLogEntries = Notification.Name("showAllLogEntries")
    static let showErrorCodesReference = Notification.Name("showErrorCodesReference")
    static let openClipLibrary = Notification.Name("openClipLibrary")
}

extension UTType {
    static var log: UTType {
        UTType(filenameExtension: "log") ?? UTType.plainText
    }
}
