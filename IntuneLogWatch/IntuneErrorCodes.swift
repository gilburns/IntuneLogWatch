//
//  IntuneErrorCodes.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 9/13/25.
//

import Foundation

struct IntuneErrorCode {
    let code: String
    let hexCode: String
    let title: String
    let description: String
    let recommendation: String

    init(hex: String, title: String, description: String, recommendation: String) {
        self.hexCode = hex.uppercased()
        // Convert hex to decimal for the code
        if let hexValue = UInt32(hex.dropFirst(2), radix: 16) {
            self.code = String(Int32(bitPattern: hexValue))
        } else {
            self.code = "Unknown"
        }
        self.title = title
        self.description = description
        self.recommendation = recommendation
    }
}

class IntuneErrorCodeLookup {
    static let shared = IntuneErrorCodeLookup()

    private let errorCodes: [String: IntuneErrorCode]

    private init() {
        let codes = [
            IntuneErrorCode(
                hex: "0x87D13BA2",
                title: "Invalid Bundle IDs",
                description: "One or more apps contain invalid bundle IDs. Intune reports that included app identifiers in the package don't match what's on the device. This usually occurs when a macOS package contains multiple app bundles and Intune thinks some are missing or unrecognized.",
                recommendation: "Verify that all bundle IDs in the package are correct. Sometimes less is more. You really only need one valid ID per app bundle."
            ),
            IntuneErrorCode(
                hex: "0x87D13B67",
                title: "App State Unknown",
                description: "Intune cannot determine the install status of the app. This often indicates the Intune agent didn't receive confirmation of success or failure. It can happen due to packaging issues or communication issues.",
                recommendation: "Check app packaging and Intune agent connectivity. Review installation logs for communication issues."
            ),
            IntuneErrorCode(
                hex: "0x87D13B66",
                title: "App Removed by User",
                description: "The app is managed, but has been removed by the user. This error means Intune installed the app, but a user or process later uninstalled it. The app is marked as Failed in Intune because it's no longer present on the device.",
                recommendation: "Consider deploying as 'Required' instead of 'Available' to prevent user removal, or educate users about managed applications."
            ),
            IntuneErrorCode(
                hex: "0x87D13B65",
                title: "Redeeming VPP Code",
                description: "The device is redeeming the redemption code. Seen with App Store (VPP) apps, it indicates the device is attempting to redeem a VPP license or App Store redemption code. The install is pending that process.",
                recommendation: "Wait for VPP redemption to complete. If it persists, check VPP license availability and Apple Business Manager configuration."
            ),
            IntuneErrorCode(
                hex: "0x87D13B64",
                title: "App Install Failed",
                description: "A generic installation failure. This can appear for many reasons (signature issues, compatibility problems, etc.) when a Mac fails to install the pushed package.",
                recommendation: "Check installation logs, verify app compatibility with macOS version, and ensure proper code signing."
            ),
            IntuneErrorCode(
                hex: "0x87D13B63",
                title: "User Rejected Install/Update",
                description: "The user rejected the offer to update/install. This means the user declined an update or install prompt for an app. (Note: On macOS, direct user prompts are rare for managed installs, but these codes might appear for VPP apps or if user interaction was needed.)",
                recommendation: "Change deployment type to 'Required' for mandatory apps, or provide user training on accepting app installations."
            ),
            IntuneErrorCode(
                hex: "0x87D13B62",
                title: "User Rejected Install/Update",
                description: "The user rejected the offer to update/install. This means the user declined an update or install prompt for an app. (Note: On macOS, direct user prompts are rare for managed installs, but these codes might appear for VPP apps or if user interaction was needed.)",
                recommendation: "Change deployment type to 'Required' for mandatory apps, or provide user training on accepting app installations."
            ),
            IntuneErrorCode(
                hex: "0x87D13B61",
                title: "Application is already installed",
                description: "The user has installed the app before managed app installation could take place",
                recommendation: "Remove the unmanaged app from the device and then re-deploy the managed app."
            ),
            IntuneErrorCode(
                hex: "0x87D30146",
                title: "App Found on Device but assignment is 'Available'",
                description: "Available App is present on the Device but the version needs to be updated.",
                recommendation: "Set the install assignment to 'Required' if you want to force an update."
            ),
            IntuneErrorCode(
                hex: "0x87D30143",
                title: "Unsupported application",
                description: "The file provided is not supported. Check the requirements for deploying the selected app type.",
                recommendation: "Check to see if the app is compatible with the macOS version or if it possibly requires that Rosetta be installed prior to deployment."
            ),
            IntuneErrorCode(
                hex: "0x87D3014D",
                title: "App Not Found on Device",
                description: "Available App is no longer present on the Device. The detection did not find the app with the given BundleID value.",
                recommendation: "Check the app detection rule. Verify the bundle ID matches the actual installed app."
            ),
            IntuneErrorCode(
                hex: "0x87D30137",
                title: "Minimum OS Requirement Not Met",
                description: "The device doesn't meet the minimum OS requirement set by the admin.",
                recommendation: "Update macOS to the minimum OS version required by the admin."
            ),
            IntuneErrorCode(
                hex: "0x87D30166", // Note: The original decimal 2016214710 was incorrect - this hex maps to -2016214682
                title: "Preinstall Script Failed",
                description: "The preinstall script provided by the admin failed. This might be expected if the preinstall script is waiting for a condition to become true before the app install can proceed.",
                recommendation: "Check the preinstall script if the error persists. The failed preinstall script will be retried at the next device check-in."
            ),
            IntuneErrorCode(
                hex: "0x87D3012F",
                title: "Internal Installation Error",
                description: "The app couldn't be installed due to an internal error.",
                recommendation: "Try installing the app manually or create a new macOS app profile. Contact Intune support if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D30130",
                title: "Internal Installation Error",
                description: "The app couldn't be installed due to an internal error.",
                recommendation: "Try installing the app manually or create a new macOS app profile. Contact Intune support if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D30136",
                title: "Internal Installation Error",
                description: "The app couldn't be installed due to an internal error.",
                recommendation: "Try installing the app manually or create a new macOS app profile. Contact Intune support if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D3013E",
                title: "DMG Contains No Supported App",
                description: "The DMG file doesn't contain any supported app. It must contain at least one .app file.",
                recommendation: "Ensure that the uploaded DMG file contains one or more .app files."
            ),
            IntuneErrorCode(
                hex: "0x87D30139",
                title: "DMG File Mount Failed",
                description: "The DMG file couldn't be mounted for installation.",
                recommendation: "Try manually mounting the DMG file to verify that the volume loads successfully. Check the DMG file if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D3013B",
                title: "Cannot Install to Applications Directory",
                description: "The app couldn't be installed to the Applications directory.",
                recommendation: "Ensure that the device can install apps locally to the Applications directory. Sync the device to retry installing the app."
            ),
            IntuneErrorCode(
                hex: "0x87D30131",
                title: "App Download Failed",
                description: "The app couldn't be downloaded. This may happen if the network is poor or the app size is large.",
                recommendation: "Check network connectivity and ensure sufficient bandwidth. Sync the device to retry installing the app."
            ),
            IntuneErrorCode(
                hex: "0x87D30132",
                title: "App Download Failed",
                description: "The app couldn't be downloaded. This may happen if the network is poor or the app size is large.",
                recommendation: "Check network connectivity and ensure sufficient bandwidth. Sync the device to retry installing the app."
            ),
            IntuneErrorCode(
                hex: "0x87D30133",
                title: "Internal Installation Error",
                description: "The app couldn't be installed due to an internal error.",
                recommendation: "Try installing the app manually or create a new macOS app profile. Contact Intune support if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D30134",
                title: "Internal Installation Error",
                description: "The app couldn't be installed due to an internal error.",
                recommendation: "Try installing the app manually or create a new macOS app profile. Contact Intune support if the error persists."
            ),
            IntuneErrorCode(
                hex: "0x87D30135",
                title: "Device Installation Error",
                description: "The app couldn't be installed due to a device error. This could be due to insufficient disk space or the app could not be written to the folder.",
                recommendation: "Ensure sufficient disk space and that the device can install apps to the Applications folder. Sync the device to retry installing the app."
            ),
            IntuneErrorCode(
                hex: "0x87D3013A",
                title: "Disk Space Exhausted",
                description: "The physical resources of this disk have been exhausted. This could be due to the hard disk running out of space or binaries of the installation files being corrupt.",
                recommendation: "Free up disk space and restart the Microsoft Intune Management Extension service. Verify installation files are not corrupt."
            )
        ]

        // Create lookup dictionaries for both decimal and hex formats
        var lookup: [String: IntuneErrorCode] = [:]
        for errorCode in codes {
            // Add both decimal and hex as keys
            lookup[errorCode.code] = errorCode
            lookup[errorCode.hexCode] = errorCode
            // Also add without 0x prefix
            if errorCode.hexCode.hasPrefix("0X") {
                lookup[String(errorCode.hexCode.dropFirst(2))] = errorCode
            }
        }

        self.errorCodes = lookup
    }

    func getErrorDetails(for code: String) -> IntuneErrorCode? {
        // Try exact match first
        if let errorCode = errorCodes[code.uppercased()] {
            return errorCode
        }

        // Try with 0x prefix if not present
        if !code.uppercased().hasPrefix("0X") {
            return errorCodes["0X\(code.uppercased())"]
        }

        return nil
    }

    func hasErrorDetails(for code: String) -> Bool {
        return getErrorDetails(for: code) != nil
    }

    func getAllErrorCodes() -> [IntuneErrorCode] {
        // Get unique error codes (since we have multiple lookup keys for the same codes)
        var uniqueCodes: [String: IntuneErrorCode] = [:]
        for (_, errorCode) in errorCodes {
            uniqueCodes[errorCode.hexCode] = errorCode
        }
        return Array(uniqueCodes.values)
    }
}
