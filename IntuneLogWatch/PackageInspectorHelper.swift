//
//  PackageInspectorHelper.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI
import AppKit

struct PackageInspectorHelper {
    
    // MARK: - Cache for package receipt checks
    
    private struct CacheEntry {
        let hasReceipt: Bool
        let timestamp: Date
    }
    
    private static var receiptCache: [String: CacheEntry] = [:]
    private static let cacheDuration: TimeInterval = 3600.0 // Cache for 1 hour
    private static let cacheQueue = DispatchQueue(label: "com.intunelogwatch.packagecache")
    
    // MARK: - Check if package exists
    
    static func hasPackageReceipt(bundleId: String) -> Bool {
        // Avoid calling during view teardown by checking for empty bundleId
        guard !bundleId.isEmpty else { return false }
        
        // Check cache first
        let cachedResult = cacheQueue.sync { () -> Bool? in
            if let entry = receiptCache[bundleId] {
                let age = Date().timeIntervalSince(entry.timestamp)
                if age < cacheDuration {
                    return entry.hasReceipt
                }
            }
            return nil
        }
        
        if let cached = cachedResult {
            return cached
        }
        
        // Not in cache or expired, perform the check
        let result = checkPackageReceipt(bundleId: bundleId)
        
        // Update cache
        cacheQueue.async {
            receiptCache[bundleId] = CacheEntry(hasReceipt: result, timestamp: Date())
        }
        
        return result
    }
    
    private static func checkPackageReceipt(bundleId: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--pkg-info", bundleId]

        // We don't care about the output here — just the exit status
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            if process.isRunning {
                process.terminate()
            }
            return false
        }
    }
    
    // MARK: - Cache management
    
    static func clearCache() {
        cacheQueue.async {
            receiptCache.removeAll()
        }
    }
    
    static func clearCache(for bundleId: String) {
        cacheQueue.async {
            receiptCache.removeValue(forKey: bundleId)
        }
    }
    
    // MARK: - Get package information
    
    static func getPackageInfo(bundleId: String) -> PackageReceiptInfo? {
        // Get package info
        guard let info = runPkgUtil(arguments: ["--pkg-info", bundleId]) else {
            return nil
        }
        
        // Get package files
        guard let files = runPkgUtil(arguments: ["--files", bundleId]) else {
            return nil
        }
        
        return PackageReceiptInfo(bundleId: bundleId, info: info, files: files)
    }
    
    // MARK: - Helper to run pkgutil commands
    
    private static func runPkgUtil(arguments: [String]) -> String? {
        
        let process = Process()
        let outputPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice // don’t buffer stderr in a pipe
        
        do {
            try process.run()
        } catch {
            return nil
        }
        
        // Read while the process is running; this drains the pipe and avoids deadlock
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            return nil
        }
        
        guard let output = String(data: outputData, encoding: .utf8),
              !output.isEmpty else {
            return nil
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Package Receipt Info Model

struct PackageReceiptInfo: Identifiable {
    let id = UUID()
    let bundleId: String
    let info: String
    let files: String

    var parsedInfo: [String: String] {
        var result: [String: String] = [:]
        let lines = info.components(separatedBy: .newlines)

        for line in lines {
            let components = line.components(separatedBy: ": ")
            if components.count >= 2 {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let value = components.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }

        return result
    }

    var fileList: [String] {
        return files.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var fullFilePaths: [String] {
        let volume = parsedInfo["volume"] ?? "/"
        let location = parsedInfo["location"] ?? ""

        return fileList.map { file in
            // If location is empty or just "/", use volume + file directly
            if location.isEmpty || location == "/" {
                return (volume as NSString).appendingPathComponent(file)
            } else {
                // Otherwise, combine volume + location + file
                let basePath = (volume as NSString).appendingPathComponent(location)
                return (basePath as NSString).appendingPathComponent(file)
            }
        }
    }
}

// MARK: - Package Receipt View

struct PackageReceiptView: View {
    let packageInfo: PackageReceiptInfo
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var pkgIcon: NSImage {
        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.icon(for: .init(filenameExtension: "pkg")!)
        } else {
            return NSWorkspace.shared.icon(forFileType: "pkg")
        }
    }

    var filteredFiles: [String] {
        if searchText.isEmpty {
            return packageInfo.fullFilePaths
        }
        return packageInfo.fullFilePaths.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Package Receipt Information")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(packageInfo.bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                // PKG icon
                Image(nsImage: pkgIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .opacity(0.7)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Package Info Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Package Information")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    if let version = packageInfo.parsedInfo["version"] {
                        infoRow(label: "Version", value: version, icon: "number.circle")
                    }

                    if let volume = packageInfo.parsedInfo["volume"] {
                        infoRow(label: "Volume", value: volume, icon: "externaldrive")
                    }

                    if let location = packageInfo.parsedInfo["location"] {
                        let displayLocation = location.isEmpty ? "/" : location
                        infoRow(label: "Location", value: displayLocation, icon: "folder")
                    }

                    if let installTime = packageInfo.parsedInfo["install-time"] {
                        let displayTime: String = {
                            if let timestamp = TimeInterval(installTime) {
                                let date = Date(timeIntervalSince1970: timestamp)
                                let formatter = DateFormatter()
                                formatter.dateStyle = .medium
                                formatter.timeStyle = .medium
                                return formatter.string(from: date)
                            } else {
                                return installTime
                            }
                        }()
                        infoRow(label: "Install Time", value: displayTime, icon: "clock")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()

            Divider()

            // Files Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Installed Files (\(filteredFiles.count)\(searchText.isEmpty ? "" : " of \(packageInfo.fullFilePaths.count)"))")
                        .font(.headline)

                    Spacer()

                    TextField("Search files...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                        .overlay(alignment: .trailing) {
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 6)
                            }
                        }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredFiles, id: \.self) { file in
                            HStack(spacing: 8) {
                                Image(systemName: fileIcon(for: file))
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                    .frame(width: 16)

                                Text(file)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)

                                Spacer()

                                // Copy button
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy path")
                                
                                // Reveal button
                                Button(action: {
                                    NSWorkspace.shared.selectFile(file, inFileViewerRootedAtPath: "")
                                }) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal path")

                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal)
                    .background(Color.gray.opacity(0.1))

                }
                
                HStack {
                    Button(action: {
                        exportPackageReport()
                    }) {
                        Label("Export Report", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .keyboardShortcut(.init("e", modifiers: [.command, .shift]))

                    Text("(⌘⇧E)")
                    
                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .presentationBackground(Color.gray.opacity(0.07))
    }

    private func exportPackageReport() {
        // Generate filename
        let sanitizedBundleId = packageInfo.bundleId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let suggestedFilename = "\(sanitizedBundleId)_pkg_report_\(dateString).txt"

        // Create NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Package Report"
        savePanel.message = "Choose where to save the package report"
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true

        // Show the save panel
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            // Build report content
            var report = ""

            // Header
            report += "================================================================================\n"
            report += "IntuneLogWatch Package Receipt Report\n"
            report += "================================================================================\n\n"

            // Package Info Section
            report += "PACKAGE INFORMATION\n"
            report += "--------------------------------------------------------------------------------\n"
            report += "Package ID: \(packageInfo.bundleId)\n"

            if let version = packageInfo.parsedInfo["version"] {
                report += "Version: \(version)\n"
            }

            if let volume = packageInfo.parsedInfo["volume"] {
                report += "Volume: \(volume)\n"
            }

            if let location = packageInfo.parsedInfo["location"] {
                let displayLocation = location.isEmpty ? "/" : location
                report += "Location: \(displayLocation)\n"
            }

            if let installTime = packageInfo.parsedInfo["install-time"] {
                if let timestamp = TimeInterval(installTime) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    report += "Install Time: \(formatter.string(from: date))\n"
                } else {
                    report += "Install Time: \(installTime)\n"
                }
            }

            report += "\n"

            // Installed Files Section
            report += "INSTALLED FILES (\(packageInfo.fullFilePaths.count) files)\n"
            report += "--------------------------------------------------------------------------------\n"

            for file in packageInfo.fullFilePaths {
                report += "\(file)\n"
            }

            report += "\n================================================================================\n"
            report += "Report generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
            report += "================================================================================\n"

            do {
                try report.write(to: url, atomically: true, encoding: .utf8)

                // Show success alert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Successful"
                    alert.informativeText = "Package report exported to \(url.lastPathComponent)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Reveal in Finder")
                    let response = alert.runModal()

                    if response == .alertSecondButtonReturn {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Failed to export report: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.caption)
                .frame(width: 20)

            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)

            Spacer()
        }
    }

    private func fileIcon(for path: String) -> String {
        
        var isDir : ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory:&isDir) {
            if isDir.boolValue {
                // file exists and is a directory
                return "folder"
            } else {
                // file exists and is not a directory
                let lowercasePath = path.lowercased()
                if lowercasePath.contains("/bin/") {
                    return "terminal"
                } else if lowercasePath.hasSuffix(".plist") || lowercasePath.hasSuffix(".json") || lowercasePath.hasSuffix(".xml") {
                    return "doc.text"
                } else if lowercasePath.hasSuffix(".txt") || lowercasePath.hasSuffix(".md") || lowercasePath.hasSuffix(".rtfd") || lowercasePath.hasSuffix(".rtf") || lowercasePath.hasSuffix(".strings") {
                    return "doc.plaintext"
                } else if lowercasePath.hasSuffix(".png") || lowercasePath.hasSuffix(".jpg") || lowercasePath.hasSuffix(".jpeg") || lowercasePath.hasSuffix(".gif") || lowercasePath.hasSuffix(".tiff") || lowercasePath.hasSuffix(".bmp") || lowercasePath.hasSuffix(".webp") || lowercasePath.hasSuffix(".heic") || lowercasePath.hasSuffix(".avif") || lowercasePath.hasSuffix(".ico") || lowercasePath.hasSuffix(".icns") || lowercasePath.hasSuffix(".svg") {
                    return "photo"
                } else if lowercasePath.hasSuffix(".dylib") || lowercasePath.hasSuffix(".framework") || lowercasePath.contains("/Frameworks/") {
                    return "shippingbox"
                } else if lowercasePath.contains("/lib/") {
                    return "books.vertical"
                } else {
                    return "doc"
                }
            }
        } else {
            // file does not exist
            return "questionmark.square"
        }
    }
}
