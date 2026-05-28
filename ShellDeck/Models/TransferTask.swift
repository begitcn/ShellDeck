import Foundation
import Observation

enum TransferType: String, CaseIterable {
    case upload
    case download

    var label: String {
        switch self {
        case .upload: return "上传"
        case .download: return "下载"
        }
    }

    var icon: String {
        switch self {
        case .upload: return "arrow.up.doc"
        case .download: return "arrow.down.doc"
        }
    }
}

enum TransferStatus: Equatable {
    case pending
    case transferring
    case completed
    case failed(String)
}

@MainActor
@Observable
final class TransferTask: Identifiable {
    let id = UUID()
    let fileName: String
    let type: TransferType
    let totalBytes: UInt64
    var transferredBytes: UInt64 = 0
    var status: TransferStatus = .pending
    let startTime = Date()

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(transferredBytes) / Double(totalBytes), 1.0)
    }

    var speed: Double {
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0 else { return 0 }
        return Double(transferredBytes) / elapsed
    }

    var speedFormatted: String {
        let bytesPerSec = speed
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    var progressFormatted: String {
        "\(Int(progress * 100))%"
    }

    init(fileName: String, type: TransferType, totalBytes: UInt64) {
        self.fileName = fileName
        self.type = type
        self.totalBytes = totalBytes
    }

    var isTerminalStatus: Bool {
        switch status {
        case .completed, .failed:
            return true
        case .pending, .transferring:
            return false
        }
    }
}
