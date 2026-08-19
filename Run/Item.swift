//
//  Item.swift
//  Run
//
//  Created by Edward Sanchez on 8/19/26.
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
