//
//  InstallHistoryParser.swift
//  IntuneLogWatch
//
//  Parses /Library/Receipts/InstallHistory.plist for MDM-pushed installs.
//

import Foundation

class InstallHistoryParser {

    // MARK: - Public API

    /// Parse InstallHistory.plist and return MDM-pushed install receipts
    func parseMDMInstalls(since date: Date? = nil) throws -> [LOBPackageReceipt] {
        let path = "/Library/Receipts/InstallHistory.plist"

        guard FileManager.default.fileExists(atPath: path) else {
            throw InstallHistoryError.fileNotFound(path)
        }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        guard let plistArray = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw InstallHistoryError.invalidFormat
        }

        return parseEntries(plistArray, since: date)
    }

    /// Parse from raw plist data (useful for testing)
    func parseEntries(_ entries: [[String: Any]], since date: Date? = nil) -> [LOBPackageReceipt] {
        return entries.compactMap { entry -> LOBPackageReceipt? in
            guard let installDate = entry["date"] as? Date,
                  let displayName = entry["displayName"] as? String,
                  let processName = entry["processName"] as? String else {
                return nil
            }

            // Filter by date if specified
            if let since = date, installDate < since {
                return nil
            }

            // Filter for MDM-pushed installs
            let displayVersion = entry["displayVersion"] as? String ?? ""
            let packageIdentifiers = entry["packageIdentifiers"] as? [String] ?? []

            guard isMDMRelatedInstall(processName: processName, displayName: displayName, displayVersion: displayVersion, packageIdentifiers: packageIdentifiers) else {
                return nil
            }

            return LOBPackageReceipt(
                packageIdentifiers: packageIdentifiers,
                displayName: displayName,
                displayVersion: displayVersion.isEmpty ? "Unknown" : displayVersion,
                installDate: installDate,
                processName: processName
            )
        }
        .sorted { $0.installDate > $1.installDate } // Newest first
    }

    // MARK: - Private

    /// Determine if an InstallHistory entry is MDM-related.
    ///
    /// MDM-pushed installs come through several paths:
    /// - "appstored": App Store apps deployed via MDM (VPP/device assignment)
    /// - "mdmclient"/"storedownloadd": Direct MDM install commands
    /// - "installer" with GUID display name: Managed PKGs pushed via InstallApplication
    ///
    /// We intentionally avoid broad heuristics (e.g. matching "Microsoft" or "Company Portal")
    /// because those are often deployed via the Intune sidecar agent, not the MDM channel.
    private func isMDMRelatedInstall(processName: String, displayName: String, displayVersion: String, packageIdentifiers: [String]) -> Bool {
        let processLower = processName.lowercased()

        // App Store apps deployed via MDM (VPP / device-based licensing)
        if processLower == "appstored" {
            return true
        }

        // Direct MDM process names
        if processLower == "mdmclient" || processLower == "storedownloadd" {
            return true
        }

        // For "installer" process: only match GUID display names (strong signal of MDM push)
        // e.g. "058f90bf-06a7-4cfe-87e6-6918a0c5aa45"
        if processLower == "installer" {
            let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
            if displayName.range(of: uuidPattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}

// MARK: - Errors

enum InstallHistoryError: LocalizedError {
    case fileNotFound(String)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "InstallHistory.plist not found at \(path)"
        case .invalidFormat:
            return "InstallHistory.plist has an unexpected format"
        }
    }
}
