//
//  AppVersionProvider.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/12/25.
//

import Foundation

enum AppVersionProvider {
    static func appVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        
        // Fallback to build version if short version not available
        if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return buildVersion
        }
        
        return "1.0.0" // Default fallback
    }
    
    static func fullVersionString() -> String {
        let version = appVersion()
        
        if let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           buildVersion != version {
            return "\(version) (build \(buildVersion))"
        }
        
        return version
    }
}
