//
//  UploadModels.swift
//  SwiftyBox
//
//  Created by Francesco on 02/03/26.
//

import Foundation

enum UploadTarget: String, CaseIterable, Identifiable {
    case catbox = "Catbox"
    case litterbox = "Litterbox"
    
    var id: Self { self }
    
    var endpointURL: URL {
        switch self {
        case .catbox:
            return URL(string: "https://catbox.moe/user/api.php")!
        case .litterbox:
            return URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!
        }
    }
}

enum LitterboxDuration: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twelveHours = "12h"
    case oneDay = "24h"
    case threeDays = "72h"
    
    var id: Self { self }
    
    var label: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .twelveHours:
            return "12 hours"
        case .oneDay:
            return "24 hours"
        case .threeDays:
            return "72 hours"
        }
    }
}

struct UploadSelection {
    let data: Data
    let filename: String
    let sizeInBytes: Int
}

struct UploadOptions {
    var target: UploadTarget
    var duration: LitterboxDuration
    var fileNameLength: Int
    var userHash: String
}
