//
//  AppVersionInformationView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/12/25.
//

import SwiftUI

struct AppVersionInformationView: View {
    let versionString: String
    let appIcon: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Use the provided app icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        NSApplication.shared.orderFrontStandardAboutPanel(self)
                    }

            } else {
                // Fallback to system icon
                Image(systemName: "app.fill")
                    .frame(width: 32, height: 32)
                    .foregroundColor(.blue)
                    .onTapGesture {
                        NSApplication.shared.orderFrontStandardAboutPanel(self)
                    }

            }


            VStack(alignment: .leading) {
                Text("IntuneLogWatch")
                    .bold()
                    .font(.title2)
                Text("v\(versionString)")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundColor(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("App version \(versionString)")
    }
}
