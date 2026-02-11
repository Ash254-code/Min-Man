//
//  Item.swift
//  ClubResults
//
//  Created by Ashley Williams on 11/2/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
