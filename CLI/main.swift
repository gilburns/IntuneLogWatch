import Foundation
import ArgumentParser

struct IntuneLogWatchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "intunelogwatch-cli",
        abstract: "Inspect MDM certificates from the command line",
        version: "1.5.0"
    )
    
    @Flag(name: .shortAndLong, help: "Output in JSON format")
    var json = false
    
    @Option(name: .shortAndLong, help: "Extract specific field (commonName, serialNumber, tenantId, etc.)")
    var field: String?
    
    @Flag(help: "List all available extensions")
    var listExtensions = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose = false
    
    @Flag(help: "Show only extension values without names")
    var valuesOnly = false
    
    func run() throws {
        if verbose {
            print("IntuneLogWatch CLI - Starting certificate inspection...")
        }
        
        let inspector = CertificateInspector()
        
        do {
            if verbose {
                print("Searching for MDM certificate...")
            }
            
            // The inspectMDMCertificate method updates the inspector's certificateInfo property asynchronously
            inspector.inspectMDMCertificate()
            
            // Wait for the inspection to complete using RunLoop
            let startTime = Date()
            let timeout: TimeInterval = 5.0
            
            while inspector.certificateInfo == nil && inspector.error == nil {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
                
                if Date().timeIntervalSince(startTime) > timeout {
                    print("Certificate inspection timed out")
                    throw ExitCode.failure
                }
            }
            
            if let error = inspector.error {
                if verbose {
                    print("Error details: \(error)")
                } else {
                    print("Error: \(error)")
                }
                throw ExitCode.failure
            }
            
            guard let certInfo = inspector.certificateInfo else {
                print("No certificate information available")
                throw ExitCode.failure
            }
            
            if verbose {
                print("Certificate found and parsed successfully")
            }
            
            // Output based on options
            if json {
                try outputJSON(certInfo)
            } else if let field = field {
                try outputField(certInfo, field: field)
            } else if listExtensions {
                outputExtensions(certInfo)
            } else {
                outputDefault(certInfo)
            }
            
        } catch {
            if verbose {
                print("Error details: \(error)")
            } else {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }
    
    // MARK: - Output Methods
    
    private func outputJSON(_ certInfo: MDMCertificateInfo) throws {
        var json: [String: Any] = [:]
        
        // Basic certificate info
        if let commonName = certInfo.commonName {
            json["commonName"] = commonName
        }
        if let issuer = certInfo.issuer {
            json["issuer"] = issuer
        }
        if let serialNumber = certInfo.serialNumber {
            json["serialNumber"] = serialNumber
        }
        if let validFrom = certInfo.validFrom {
            json["notValidBefore"] = ISO8601DateFormatter().string(from: validFrom)
        }
        if let validTo = certInfo.validTo {
            json["notValidAfter"] = ISO8601DateFormatter().string(from: validTo)
        }
        
        // Fingerprints
        json["fingerprints"] = [
            "sha1": certInfo.fingerprints.sha1,
            "sha256": certInfo.fingerprints.sha256,
            "md5": certInfo.fingerprints.md5
        ]
        
        // Extensions
        var extensions: [String: Any] = [:]
        for ext in certInfo.extensions {
            extensions[ext.oid] = [
                "name": ext.name,
                "value": ext.value
            ]
        }
        json["extensions"] = extensions
        
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
    
    private func outputField(_ certInfo: MDMCertificateInfo, field: String) throws {
        let fieldLower = field.lowercased()
        
        switch fieldLower {
        case "commonname", "cn":
            print(certInfo.commonName ?? "")
        case "issuer":
            print(certInfo.issuer ?? "")
        case "serialnumber", "serial":
            print(certInfo.serialNumber ?? "")
        case "notvalidbefore", "validfrom":
            if let date = certInfo.validFrom {
                print(DateFormatter.readable.string(from: date))
            }
        case "notvalidafter", "validto":
            if let date = certInfo.validTo {
                print(DateFormatter.readable.string(from: date))
            }
        case "tenantid":
            if let ext = findExtension(certInfo, oid: "1.2.840.113556.5.14") {
                print(ext.value)
            }
        case "deviceid", "intunedeviceid":
            if let ext = findExtension(certInfo, oid: "1.2.840.113556.5.4") {
                print(ext.value)
            }
        case "userid", "entrauserid":
            if let ext = findExtension(certInfo, oid: "1.2.840.113556.5.10") {
                print(ext.value)
            }
        case "accountid":
            if let ext = findExtension(certInfo, oid: "1.2.840.113556.5.6") {
                print(ext.value)
            }
        case "enrollmentid", "mdmenrollmentid":
            if let ext = findExtension(certInfo, oid: "1.2.840.113556.5.15") {
                print(ext.value)
            }
        case "sha1", "sha1fingerprint":
            print(certInfo.fingerprints.sha1)
        case "sha256", "sha256fingerprint":
            print(certInfo.fingerprints.sha256)
        case "md5", "md5fingerprint":
            print(certInfo.fingerprints.md5)
        default:
            // Try to find by extension name or OID
            if let ext = certInfo.extensions.first(where: { 
                $0.name.lowercased().contains(fieldLower) || $0.oid == field 
            }) {
                print(ext.value)
            } else {
                print("Field '\(field)' not found", to: &StandardError.shared)
                throw ExitCode.failure
            }
        }
    }
    
    private func outputExtensions(_ certInfo: MDMCertificateInfo) {
        if certInfo.extensions.isEmpty {
            print("No extensions found")
            return
        }
        
        for ext in certInfo.extensions.sorted(by: { $0.name < $1.name }) {
            if valuesOnly {
                print(ext.value)
            } else {
                print("\(ext.name): \(ext.value)")
                if verbose {
                    print("  OID: \(ext.oid)")
                }
            }
        }
    }
    
    private func outputDefault(_ certInfo: MDMCertificateInfo) {
        print("MDM Certificate Information")
        print("==========================")
        
        if let commonName = certInfo.commonName {
            print("Common Name: \(commonName)")
        }
        if let issuer = certInfo.issuer {
            print("Issuer: \(issuer)")
        }
        if let serialNumber = certInfo.serialNumber {
            print("Serial Number: \(serialNumber)")
        }
        if let validFrom = certInfo.validFrom {
            print("Not Valid Before: \(DateFormatter.readable.string(from: validFrom))")
        }
        if let validTo = certInfo.validTo {
            print("Not Valid After: \(DateFormatter.readable.string(from: validTo))")
        }
        
        if !certInfo.extensions.isEmpty {
            print("\nMicrosoft Intune Extensions")
            print("==========================")
            
            // Sort extensions in the same order as the GUI
            let sortedExtensions = sortExtensions(certInfo.extensions)
            
            for ext in sortedExtensions {
                print("\(ext.name): \(ext.value)")
                if verbose {
                    print("  OID: \(ext.oid)")
                }
            }
        }
        
        // Add fingerprints section
        print("\nCertificate Fingerprints")
        print("=======================")
        print("SHA-256: \(certInfo.fingerprints.sha256)")
        print("SHA-1: \(certInfo.fingerprints.sha1)")
        print("MD5: \(certInfo.fingerprints.md5)")
    }
    
    // MARK: - Helper Methods
    
    private func findExtension(_ certInfo: MDMCertificateInfo, oid: String) -> CertificateExtension? {
        return certInfo.extensions.first { $0.oid == oid }
    }
    
    private func sortExtensions(_ extensions: [CertificateExtension]) -> [CertificateExtension] {
        let preferredOrder = [
            "1.2.840.113556.5.4",   // Intune Device ID
            "1.2.840.113556.5.14",  // TenantID
            "1.2.840.113556.5.10",  // Entra User ID
            "1.2.840.113556.5.6",   // AccountID
            "1.2.840.113556.5.15",  // MdmEnrollmentID
            "1.2.840.113556.5.16",  // PolicyID
            "1.2.840.113556.5.17",  // ResourceID
            "1.2.840.113556.5.18",  // ProfileID
            "1.2.840.113556.5.11",  // Unknown ID
            "1.2.840.113556.5.19"   // OID_1_2_840_113556_5_19
        ]
        
        return extensions.sorted { ext1, ext2 in
            let index1 = preferredOrder.firstIndex(of: ext1.oid) ?? Int.max
            let index2 = preferredOrder.firstIndex(of: ext2.oid) ?? Int.max
            return index1 < index2
        }
    }
}

// MARK: - Standard Error Output

struct StandardError: TextOutputStream {
    static var shared = StandardError()
    
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let readable: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Main Entry Point

IntuneLogWatchCLI.main()
