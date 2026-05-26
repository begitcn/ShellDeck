import Foundation
import SwiftData

enum AuthType: String, Codable, CaseIterable {
    case password
    case privateKey

    var displayName: String {
        switch self {
        case .password: "密码"
        case .privateKey: "密钥"
        }
    }
}

@Model
final class Server {
    var id: UUID
    var displayName: String
    var host: String
    var port: Int
    var username: String
    var authType: String
    var group: ServerGroup?
    var sortOrder: Int?
    var createdAt: Date
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String = "",
        host: String,
        port: Int = 22,
        username: String,
        authType: AuthType = .password,
        sortOrder: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.authType = authType.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var authTypeEnum: AuthType {
        get { AuthType(rawValue: authType) ?? .password }
        set { authType = newValue.rawValue }
    }
}
