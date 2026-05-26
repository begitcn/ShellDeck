import Foundation
import SwiftData

@Model
final class ServerGroup {
    var id: UUID
    var name: String
    var sortOrder: Int

    @Relationship(inverse: \Server.group) var servers: [Server]

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.servers = []
    }
}
