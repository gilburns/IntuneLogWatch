//
//  CertificateInspectionView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/25/25.
//

import SwiftUI

struct CertificateInspectionView: View {
    @StateObject private var inspector = CertificateInspector()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                headerSection
                
                if inspector.isLoading {
                    loadingSection
                } else if let error = inspector.error {
                    errorSection(error)
                } else if let certificateInfo = inspector.certificateInfo {
                    certificateDetailsSection(certificateInfo)
                } else {
                    initialSection
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 600, minHeight: 500)
            .background(Color(.windowBackgroundColor))
            .navigationTitle("MDM Certificate Inspector")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            inspector.inspectMDMCertificate()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("MDM Certificate Inspector")
                .font(.title2)
                .fontWeight(.semibold)
            
            Grid(alignment: .center) {
                GridRow {
                    Text("Inspecting certificate with issuer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Microsoft Intune MDM Device CA")
                        .font(.caption)
                        .foregroundColor(.blue)
                }.multilineTextAlignment(.center)
            }
        }
    }
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching system keychain for MDM certificate...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.headline)
            
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Try Again") {
                inspector.inspectMDMCertificate()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var initialSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("Ready to Inspect")
                .font(.headline)
            
            Text("Click 'Inspect Certificate' to search for and analyze the MDM certificate")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func certificateDetailsSection(_ info: MDMCertificateInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                certificateBasicInfo(info)
                
                if !info.extensions.isEmpty {
                    extensionsSection(info.extensions)
                }
                
                fingerprintsSection(info.fingerprints)
            }
        }
    }
    
    private func certificateBasicInfo(_ info: MDMCertificateInfo) -> some View {
        GroupBox("Certificate Information") {
            VStack(alignment: .leading, spacing: 12) {
                
                if let commonName = info.commonName {
                    InfoRow(label: "Common Name", value: commonName)
                }
                
                if let issuer = info.issuer {
                    InfoRow(label: "Issuer", value: issuer)
                }
                
                if let serialNumber = info.serialNumber {
                    InfoRow(label: "Serial Number", value: serialNumber)
                }
                
                if let validFrom = info.validFrom {
                    InfoRow(label: "Not Valid Before", value: DateFormatter.readable.string(from: validFrom))
                }
                
                if let validTo = info.validTo {
                    InfoRow(label: "Not Valid After", value: DateFormatter.readable.string(from: validTo))
                }
            }
            .padding(.vertical, 8)
        }
        .backgroundStyle(.regularMaterial)
        .foregroundColor(.primary)
    }
    
    private func extensionsSection(_ extensions: [CertificateExtension]) -> some View {
        GroupBox("Microsoft Intune Extensions") {
            VStack(alignment: .leading, spacing: 12) {
                
//                Text("The following extensions contain Intune enrollment information:")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .padding(.bottom, 8)
                
                ForEach(sortedExtensions(extensions)) { ext in
                    ExtensionRow(ext: ext)
                    
                    if ext.id != sortedExtensions(extensions).last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .backgroundStyle(.regularMaterial)
        .foregroundColor(.primary)
    }
    
    private func fingerprintsSection(_ fingerprints: CertificateFingerprints) -> some View {
        GroupBox("Certificate Fingerprints") {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "SHA-256", value: fingerprints.sha256)
                InfoRow(label: "SHA-1", value: fingerprints.sha1)
                InfoRow(label: "MD5", value: fingerprints.md5)
            }
            .padding(.vertical, 8)
        }
        .backgroundStyle(.regularMaterial)
        .foregroundColor(.primary)
    }
    
    private func sortedExtensions(_ extensions: [CertificateExtension]) -> [CertificateExtension] {
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

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ExtensionRow: View {
    let ext: CertificateExtension
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(ext.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("OID: \(ext.oid)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospaced()
            }
            
            Text(ext.value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
    }
}

extension DateFormatter {
    static let readable: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
