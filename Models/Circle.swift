import Foundation
import SwiftUI

struct Circle: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var colorHex: String
    var viewMode: ViewMode
    let createdAt: Date
    var updatedAt: Date

    // Locally loaded
    var members: [Contact] = []

    enum ViewMode: String, Codable {
        case list, tree
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case userId    = "user_id"
        case colorHex  = "color_hex"
        case viewMode  = "view_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    init(id: UUID = UUID(), userId: UUID, name: String, colorHex: String = "#4F8EF7", viewMode: ViewMode = .list) {
        self.id = id
        self.userId = userId
        self.name = name
        self.colorHex = colorHex
        self.viewMode = viewMode
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct CircleMember: Codable {
    let circleId: UUID
    let contactId: UUID
    let userId: UUID
    var parentContactId: UUID?

    enum CodingKeys: String, CodingKey {
        case circleId         = "circle_id"
        case contactId        = "contact_id"
        case userId           = "user_id"
        case parentContactId  = "parent_contact_id"
    }
}
