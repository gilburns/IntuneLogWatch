//
//  AppIconHelper.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI
import AppKit

class AppIconHelper: ObservableObject {
    static let shared = AppIconHelper()
    
    private var iconCache: [String: NSImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.intunelogwatch.iconCache", attributes: .concurrent)
    
    private init() {}
    
    func getIcon(for bundleId: String) -> NSImage? {
        return cacheQueue.sync {
            // Check cache first (thread-safe read)
            if let cachedIcon = iconCache[bundleId] {
                return cachedIcon
            }
            
            // Icon not in cache, fetch it
            let workspace = NSWorkspace.shared
            var newIcon: NSImage?
            
            // Try to get the app icon by bundle identifier
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                newIcon = workspace.icon(forFile: appURL.path)
            }
            
            // Try alternative methods for common bundle patterns
            if newIcon == nil {
                newIcon = getIconByAlternativeMethods(bundleId: bundleId)
            }
            
            // Cache the result (even if nil to avoid repeated lookups)
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.iconCache[bundleId] = newIcon
            }
            
            return newIcon
        }
    }
    
    private func getIconByAlternativeMethods(bundleId: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        
        // Try to find the app in common locations
        let commonPaths = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/usr/local/bin"
        ]
        
        for basePath in commonPaths {
            let fileManager = FileManager.default
            
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: basePath)
                
                for item in contents {
                    let fullPath = "\(basePath)/\(item)"
                    
                    if item.hasSuffix(".app") {
                        if let bundle = Bundle(path: fullPath),
                           let appBundleId = bundle.bundleIdentifier,
                           appBundleId == bundleId {
                            let icon = workspace.icon(forFile: fullPath)
                            return icon
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
}

struct AppIconView: View {
    let bundleId: String?
    let policyType: PolicyType
    let size: CGFloat
    
    @StateObject private var iconHelper = AppIconHelper.shared
    @State private var appIcon: NSImage?
    
    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .cornerRadius(size * 0.15) // Rounded corners like app icons
            } else {
                fallbackIcon
            }
        }
        .onAppear {
            loadIcon()
        }
        .onChange(of: bundleId) { oldValue, newValue in
            appIcon = nil // Clear the current icon immediately
            loadIcon()
        }
        .onChange(of: policyType) { oldValue, newValue in
            appIcon = nil // Clear when policy type changes
            loadIcon()
        }
    }
    
    private var fallbackIcon: some View {
        Group {
            switch policyType {
            case .app:
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
                    .font(.system(size: size * 0.8))
                    .frame(width: size, height: size)
            case .script:
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                    .font(.system(size: size * 0.8))
                    .frame(width: size, height: size)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: size * 0.8))
                    .frame(width: size, height: size)
            }
        }
    }
    
    private func loadIcon() {
        guard let bundleId = bundleId, policyType == .app else {
            appIcon = nil
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = iconHelper.getIcon(for: bundleId)
            
            DispatchQueue.main.async {
                self.appIcon = icon
            }
        }
    }
}
