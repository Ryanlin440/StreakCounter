//
//  Item.swift
//  StreakCounter
//
//  Created by Ryan Lin on 6/7/26.
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
