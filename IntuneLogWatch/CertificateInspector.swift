//
//  CertificateInspector.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/25/25.
//

import Foundation
import Security
import CryptoKit

struct CertificateExtension: Identifiable {
    let id = UUID()
    let oid: String
    let name: String
    let value: String
    let isCritical: Bool
}

struct CertificateFingerprints {
    let sha1: String
    let sha256: String
    let md5: String
}

struct MDMCertificateInfo {
    let commonName: String?
    let issuer: String?
    let serialNumber: String?
    let validFrom: Date?
    let validTo: Date?
    let fingerprints: CertificateFingerprints
    let extensions: [CertificateExtension]
}

class CertificateInspector: ObservableObject {
    @Published var certificateInfo: MDMCertificateInfo?
    @Published var error: String?
    @Published var isLoading = false
    
    
    func inspectMDMCertificate() {
        isLoading = true
        error = nil
        certificateInfo = nil
        
        Task {
            do {
                let certificate = try await findMDMCertificate()
                let info = try extractCertificateInfo(from: certificate)
                
                await MainActor.run {
                    self.certificateInfo = info
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func findMDMCertificate() async throws -> SecCertificate {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassCertificate,
                    kSecMatchLimit as String: kSecMatchLimitAll,
                    kSecReturnRef as String: true
                ]
                
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess else {
                    continuation.resume(throwing: CertificateError.keychainAccessFailed("Failed to access keychain: \(status)"))
                    return
                }
                
                guard let certificates = result as? [SecCertificate] else {
                    continuation.resume(throwing: CertificateError.noCertificatesFound)
                    return
                }
                
                var intuneAgentCert: SecCertificate?
                var mdmDeviceCert: SecCertificate?
                
                // Look for certificates with Microsoft Intune OIDs and categorize them
                for certificate in certificates {
                    if CertificateInspector.hasMicrosoftIntuneOIDs(certificate) {
                        var commonName: CFString?
                        SecCertificateCopyCommonName(certificate, &commonName)
                        let subject = commonName as String? ?? "Unknown"
                        
                        if subject.hasPrefix("IntuneMDMAgent-") {
                            intuneAgentCert = certificate
                        } else if CertificateInspector.isGUIDOnlyName(subject) {
                            mdmDeviceCert = certificate
                        }
                    }
                }
                
                // Prefer the GUID-only certificate (actual MDM device cert)
                if let deviceCert = mdmDeviceCert {
                    continuation.resume(returning: deviceCert)
                } else if let agentCert = intuneAgentCert {
                    continuation.resume(returning: agentCert)
                } else {
                    continuation.resume(throwing: CertificateError.mdmCertificateNotFound)
                }
            }
        }
    }
    
    private static func hasMicrosoftIntuneOIDs(_ certificate: SecCertificate) -> Bool {
        // Use Security framework to check for Microsoft Intune OIDs directly
        guard let certDict = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] else {
            return false
        }
        
        // Check if any of the Microsoft Intune OIDs are present
        let intuneOIDs = [
            "1.2.840.113556.5.4",   // Intune Device ID
            "1.2.840.113556.5.6",   // AccountID
            "1.2.840.113556.5.10",  // Entra User ID
            "1.2.840.113556.5.14",  // TenantID
            "1.2.840.113556.5.15",  // MdmEnrollmentID
            "1.2.840.113556.5.16",  // PolicyID
            "1.2.840.113556.5.17",  // ResourceID
            "1.2.840.113556.5.18"   // ProfileID
        ]
        
        for oid in intuneOIDs {
            if certDict.keys.contains(oid) {
                return true
            }
        }
        
        return false
    }
    
    private static func isGUIDOnlyName(_ commonName: String) -> Bool {
        // Check if the common name is a GUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        let guidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let regex = try? NSRegularExpression(pattern: guidPattern)
        let range = NSRange(location: 0, length: commonName.utf16.count)
        return regex?.firstMatch(in: commonName, options: [], range: range) != nil
    }
    
    private func calculateFingerprints(from certificate: SecCertificate) -> CertificateFingerprints {
        let certData = SecCertificateCopyData(certificate)
        let data = Data(bytes: CFDataGetBytePtr(certData), count: CFDataGetLength(certData))
        
        // Calculate SHA-256 fingerprint
        let sha256Hash = SHA256.hash(data: data)
        let sha256String = sha256Hash.compactMap { String(format: "%02X", $0) }.joined(separator: " ")
        
        // Calculate SHA-1 fingerprint
        let sha1Hash = Insecure.SHA1.hash(data: data)
        let sha1String = sha1Hash.compactMap { String(format: "%02X", $0) }.joined(separator: " ")
        
        // Calculate MD5 fingerprint
        let md5Hash = Insecure.MD5.hash(data: data)
        let md5String = md5Hash.compactMap { String(format: "%02X", $0) }.joined(separator: " ")
        
        return CertificateFingerprints(
            sha1: sha1String,
            sha256: sha256String,
            md5: md5String
        )
    }
    
    private func extractCertificateInfo(from certificate: SecCertificate) throws -> MDMCertificateInfo {
        let certData = SecCertificateCopyData(certificate)
        _ = Data(bytes: CFDataGetBytePtr(certData), count: CFDataGetLength(certData))
        
        var commonName: CFString?
        SecCertificateCopyCommonName(certificate, &commonName)
        
        // Extract certificate properties using Security framework
        let extensions = extractExtensionsUsingSecurity(from: certificate)
        let serialNumber = extractSerialNumberUsingSecurity(from: certificate)
        let (validFrom, validTo) = extractValidityUsingSecurity(from: certificate)
        let fingerprints = calculateFingerprints(from: certificate)
        
        return MDMCertificateInfo(
            commonName: commonName as String?,
            issuer: "Microsoft Intune MDM Device CA",
            serialNumber: serialNumber,
            validFrom: validFrom,
            validTo: validTo,
            fingerprints: fingerprints,
            extensions: extensions
        )
    }
    
    private func extractExtensionsUsingSecurity(from certificate: SecCertificate) -> [CertificateExtension] {
        var extensions: [CertificateExtension] = []
        
        let targetOIDs = [
            "1.2.840.113556.5.4": "Intune Device ID",
            "1.2.840.113556.5.6": "Account ID",
            "1.2.840.113556.5.10": "Entra User ID",
            "1.2.840.113556.5.11": "OID_1.2.840.113556.5.11",
            "1.2.840.113556.5.14": "Tenant ID",
            "1.2.840.113556.5.15": "MdmEnrollment ID",
            "1.2.840.113556.5.16": "Policy ID",
            "1.2.840.113556.5.17": "Resource ID",
            "1.2.840.113556.5.18": "Profile ID",
            "1.2.840.113556.5.19": "OID_1.2.840.113556.5.19"
        ]
        
        // Get certificate values using Security framework
        guard let certDict = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] else {
            return extensions
        }
        
        
        // Look for extensions in the certificate dictionary
        for (key, value) in certDict {
            if let valueDict = value as? [String: Any] {
                if let label = valueDict[kSecPropertyKeyLabel as String] as? String {
                    
                    // Check if this is an extension section
                    if label.lowercased().contains("extension") {
                        // Try to extract extensions data
                        if let extensionsArray = valueDict[kSecPropertyKeyValue as String] as? [[String: Any]] {
                            for extDict in extensionsArray {
                                if let extLabel = extDict[kSecPropertyKeyLabel as String] as? String {
                                    for (oid, name) in targetOIDs {
                                        if extLabel.contains(oid) {
                                            if let extValue = extractExtensionValue(from: extDict) {
                                                extensions.append(CertificateExtension(
                                                    oid: oid,
                                                    name: name,
                                                    value: extValue,
                                                    isCritical: false
                                                ))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Also check if the label directly contains our OIDs
                    for (oid, name) in targetOIDs {
                        if label.contains(oid) || key.contains(oid) {
                            if let extensionValue = extractExtensionValue(from: valueDict) {
                                extensions.append(CertificateExtension(
                                    oid: oid,
                                    name: name,
                                    value: extensionValue,
                                    isCritical: false
                                ))
                            } else {
                            }
                        }
                    }
                }
            }
        }
        
        // If we didn't find extensions in the standard way, try alternative approach
        if extensions.isEmpty {
            extensions = extractExtensionsFromCertData(certificate: certificate, targetOIDs: targetOIDs)
        }
        
        return extensions
    }
    
    private func extractExtensionsFromCertData(certificate: SecCertificate, targetOIDs: [String: String]) -> [CertificateExtension] {
        var extensions: [CertificateExtension] = []
        
        let certData = SecCertificateCopyData(certificate)
        let data = Data(bytes: CFDataGetBytePtr(certData), count: CFDataGetLength(certData))
                
        // Try to find each specific OID
        for (oid, name) in targetOIDs {
            if let value = searchForOIDInCertData(data: data, oid: oid) {
                extensions.append(CertificateExtension(
                    oid: oid,
                    name: name,
                    value: value,
                    isCritical: false
                ))
            }
        }
        
        // Also try searching for the literal OID strings in the certificate
        for (oid, name) in targetOIDs {
            if let oidData = oid.data(using: .utf8),
               let oidRange = data.range(of: oidData) {
                // Try to extract value after the OID
                let searchStart = oidRange.upperBound
                let searchEnd = min(searchStart + 100, data.endIndex)
                let valueData = data[searchStart..<searchEnd]
                
                if let stringValue = extractPrintableString(from: valueData) {
                    extensions.append(CertificateExtension(
                        oid: oid,
                        name: name,
                        value: stringValue,
                        isCritical: false
                    ))
                }
            }
        }
        
        return extensions
    }
    
    private func encodeDERObjectIdentifier(_ oid: String) -> Data {
        let components = oid.components(separatedBy: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return Data() }
        
        var result = Data()
        
        // First byte encodes first two components
        result.append(UInt8(components[0] * 40 + components[1]))
        
        // Remaining components use variable length encoding
        for component in components.dropFirst(2) {
            if component < 128 {
                result.append(UInt8(component))
            } else {
                // Multi-byte encoding
                var value = component
                var bytes: [UInt8] = []
                
                bytes.append(UInt8(value & 0x7F))
                value >>= 7
                
                while value > 0 {
                    bytes.append(UInt8((value & 0x7F) | 0x80))
                    value >>= 7
                }
                
                result.append(contentsOf: bytes.reversed())
            }
        }
        
        return result
    }
    
    private func searchForOIDInCertData(data: Data, oid: String) -> String? {
        // Use the improved DER encoding function
        let derOID = encodeDERObjectIdentifier(oid)
        
        
        // Search for this OID in the certificate data
        if let oidRange = data.range(of: derOID) {
            
            // Try to find the associated value after the OID
            let searchStart = oidRange.upperBound
            let searchRange = searchStart..<min(searchStart + 200, data.endIndex)
            let searchData = data[searchRange]
            
            
            // Look for printable strings or UTF8 strings in the next 200 bytes
            if let stringValue = extractPrintableString(from: searchData) {
                return stringValue
            }
            
            // If no printable string found, return hex representation of first 32 bytes
            let valueBytes = searchData.prefix(32)
            let hexValue = valueBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            return hexValue
        } else {
        }
        
        return nil
    }
    
    private func extractPrintableString(from data: Data) -> String? {
        // Look for ASN.1 PrintableString (tag 0x13) or UTF8String (tag 0x0C)
        var index = 0
        
        guard data.count > 2 else { return nil }
        
        while index < data.count - 2 {
            guard index < data.count else { break }
            
            let tag = data[index]
            
            guard index + 1 < data.count else { break }
            let length = Int(data[index + 1])
            
            // Validate length is reasonable and within bounds
            guard length > 0 && length < 1000 && index + 2 + length <= data.count else {
                index += 1
                continue
            }
            
            if tag == 0x13 || tag == 0x0C {
                let stringData = data[(index + 2)..<(index + 2 + length)]
                if let string = String(data: stringData, encoding: .utf8), !string.isEmpty {
                    // Check if it's a reasonable looking string (not just random bytes)
                    if string.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "." || $0 == "@") }) {
                        return string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            
            index += 1
        }
        
        return nil
    }
    
    private func extractExtensionValue(from valueDict: [String: Any]) -> String? {
        
        if let value = valueDict[kSecPropertyKeyValue as String] {
            
            if let stringValue = value as? String {
                return stringValue
            } else if let dataValue = value as? Data {
                // Try to convert data to string
                if let stringValue = String(data: dataValue, encoding: .utf8) {
                    return stringValue
                } else {
                    // Return hex representation
                    let hexString = dataValue.map { String(format: "%02X", $0) }.joined(separator: " ")
                    return hexString
                }
            } else if let numberValue = value as? NSNumber {
                let stringValue = numberValue.stringValue
                return stringValue
            } else if let arrayValue = value as? [Any] {
                
                // Look for the "Unparsed Data" item in the array
                for item in arrayValue {
                    if let itemDict = item as? [String: Any],
                       let label = itemDict["label"] as? String,
                       label == "Unparsed Data" {
                        
                        
                        if let itemValue = itemDict["value"] {
                            
                            if let dataValue = itemValue as? Data {
                                
                                // Try to decode the data based on its structure
                                return decodeExtensionData(dataValue)
                            } else if let stringValue = itemValue as? String {
                                return stringValue
                            } else {
                                return String(describing: itemValue)
                            }
                        }
                    }
                }
                
                return "Array with \(arrayValue.count) items"
            } else {
                return String(describing: value)
            }
        } else {
        }
        
        return nil
    }
    
    private func decodeExtensionData(_ data: Data) -> String {
        // The data contains ASN.1 encoded extension value
        // Most Microsoft Intune extensions contain simple values
        
        if data.count == 0 {
            return "Empty data"
        }
        
        
        // Check if it starts with ASN.1 OCTET STRING tag (0x04)
        if data.count > 2 && data[0] == 0x04 {
            let length = Int(data[1])
            if length > 0 && data.count >= 2 + length {
                let valueData = data[2..<(2 + length)]
                
                // Try to decode as string first
                if let stringValue = String(data: valueData, encoding: .utf8) {
                    return stringValue
                } else if let stringValue = String(data: valueData, encoding: .ascii) {
                    return stringValue
                }
                
                // If not a string, check if it looks like a GUID/UUID (16 bytes)
                if valueData.count == 16 {
                    // Format as Microsoft GUID with correct byte ordering
                    // First 4 bytes (DWORD): little-endian
                    // Next 2 bytes (WORD): little-endian  
                    // Next 2 bytes (WORD): little-endian
                    // Last 8 bytes: big-endian
                    let bytes = Array(valueData)
                    let guid = String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                                bytes[3], bytes[2], bytes[1], bytes[0],  // First DWORD (little-endian)
                                bytes[5], bytes[4],                      // First WORD (little-endian)
                                bytes[7], bytes[6],                      // Second WORD (little-endian)
                                bytes[8], bytes[9],                      // Last 8 bytes (big-endian)
                                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
                    return guid
                }
                
                // Return as hex string
                let hexString = valueData.map { String(format: "%02X", $0) }.joined(separator: " ")
                return hexString
            }
        }
        
        // Check if it starts with ASN.1 INTEGER tag (0x02)
        if data.count > 2 && data[0] == 0x02 {
            let length = Int(data[1])
            if length > 0 && data.count >= 2 + length {
                let valueData = data[2..<(2 + length)]
                
                // Convert integer bytes to number
                var value: UInt64 = 0
                for byte in valueData {
                    value = (value << 8) | UInt64(byte)
                }
                return String(value)
            }
        }
        
        // Check if it starts with ASN.1 UTF8String tag (0x0C) or PrintableString (0x13)
        if data.count > 2 && (data[0] == 0x0C || data[0] == 0x13) {
            let length = Int(data[1])
            if length > 0 && data.count >= 2 + length {
                let valueData = data[2..<(2 + length)]
                if let stringValue = String(data: valueData, encoding: .utf8) {
                    return stringValue
                }
            }
        }
        
        // Check if it's raw 16-byte GUID (like UserSID)
        if data.count == 16 {
            let bytes = Array(data)
            let guid = String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                        bytes[3], bytes[2], bytes[1], bytes[0],  // First DWORD (little-endian)
                        bytes[5], bytes[4],                      // First WORD (little-endian)
                        bytes[7], bytes[6],                      // Second WORD (little-endian)
                        bytes[8], bytes[9],                      // Last 8 bytes (big-endian)
                        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
            return guid
        }
        
        // Fallback: return as hex
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        return hexString
    }
    
    private func extractSerialNumberUsingSecurity(from certificate: SecCertificate) -> String? {
        guard let certDict = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] else {
            return nil
        }
        
        
        // Look for serial number in certificate properties
        for (key, value) in certDict {
            if let valueDict = value as? [String: Any],
               let label = valueDict[kSecPropertyKeyLabel as String] as? String {
                
                
                if label.lowercased().contains("serial") || key.lowercased().contains("serial") {
                    
                    if let serialValue = valueDict[kSecPropertyKeyValue as String] {
                        
                        if let stringValue = serialValue as? String {
                            return stringValue
                        } else if let dataValue = serialValue as? Data {
                            let hexString = dataValue.map { String(format: "%02X", $0) }.joined(separator: " ")
                            return hexString
                        } else if let numberValue = serialValue as? NSNumber {
                            let hexString = String(format: "%02X", numberValue.uint64Value)
                            return hexString
                        }
                    }
                }
            }
        }
        
        return nil
    }

    private func extractValidityUsingSecurity(from certificate: SecCertificate) -> (Date?, Date?) {
        guard let certDict = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] else {
            return (nil, nil)
        }
        
        var validFrom: Date?
        var validTo: Date?
        
        
        for (_, value) in certDict {
            if let valueDict = value as? [String: Any],
               let label = valueDict[kSecPropertyKeyLabel as String] as? String {
                
                if label.lowercased().contains("not valid before") || label.lowercased().contains("not before") {
                    if let dateValue = valueDict[kSecPropertyKeyValue as String] as? Date {
                        validFrom = dateValue
                    } else if let timestamp = valueDict[kSecPropertyKeyValue as String] as? TimeInterval {
                        validFrom = Date(timeIntervalSinceReferenceDate: timestamp)
                    } else if let timestampNumber = valueDict[kSecPropertyKeyValue as String] as? NSNumber {
                        validFrom = Date(timeIntervalSinceReferenceDate: timestampNumber.doubleValue)
                    }
                } else if label.lowercased().contains("not valid after") || label.lowercased().contains("not after") {
                    if let dateValue = valueDict[kSecPropertyKeyValue as String] as? Date {
                        validTo = dateValue
                    } else if let timestamp = valueDict[kSecPropertyKeyValue as String] as? TimeInterval {
                        validTo = Date(timeIntervalSinceReferenceDate: timestamp)
                    } else if let timestampNumber = valueDict[kSecPropertyKeyValue as String] as? NSNumber {
                        validTo = Date(timeIntervalSinceReferenceDate: timestampNumber.doubleValue)
                    }
                }
            }
        }
        
        return (validFrom, validTo)
    }
}

enum CertificateError: LocalizedError {
    case keychainAccessFailed(String)
    case noCertificatesFound
    case mdmCertificateNotFound
    case failedToExtractData
    
    var errorDescription: String? {
        switch self {
        case .keychainAccessFailed(let message):
            return "Keychain access failed: \(message)"
        case .noCertificatesFound:
            return "No certificates found in keychain"
        case .mdmCertificateNotFound:
            return "MDM certificate with issuer 'Microsoft Intune MDM Device CA' not found"
        case .failedToExtractData:
            return "Failed to extract certificate data"
        }
    }
}
