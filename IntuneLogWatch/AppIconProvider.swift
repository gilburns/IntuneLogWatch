//
//  AppIconProvider.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/12/25.
//

import Foundation
import AppKit

enum AppIconProvider {
    static func appIcon() -> NSImage? {
        // Return the app's icon image
        return NSApplication.shared.applicationIconImage
    }
    
    static func appIconName() -> String {
        // Try to get the icon file name from Info.plist
        if let iconFileName = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String {
            return iconFileName
        }
        
        // Fallback to app name
        if let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            return appName
        }
        
        return "IntuneLogWatch"
    }
}
