//
//  Bundle.swift
//  StartToSwiftUI
//
//  Created by Andrey Efimov on 26.11.2025.
//

import Foundation

extension Bundle {
        
    var minimumiOSVersion: String {
            return infoDictionary?["MinimumOSVersion"] as? String ?? "Unknown"
        }

    var version: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var build: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var versionBuild: String {
        return "\(version) (\(build))"
    }
}
