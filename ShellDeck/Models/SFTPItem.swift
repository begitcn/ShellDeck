import Foundation

struct SFTPItem: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modificationTime: Date?

    var id: String { path }
}
