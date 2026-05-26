import Foundation
import Citadel
import NIOCore

enum MonitorError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "监控命令执行失败: \(msg)"
        }
    }
}

@MainActor
@Observable
final class MonitorService {
    private(set) var cpuHistory: [MetricPoint] = []
    private(set) var memoryHistory: [MetricPoint] = []
    private(set) var diskUsed: Double = 0.0
    private(set) var diskTotal: Double = 0.0

    private var monitoringTask: Task<Void, Never>?
    private weak var client: SSHClient?

    private let maxHistory = 20
    private let pollInterval: UInt64 = 3_000_000_000

    func startMonitoring(client: SSHClient) {
        self.client = client
        stopMonitoring()

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await pollDisk()
                } catch {
                    print("[ShellDeck] Disk poll error: \(error)")
                }

                do {
                    let mem = try await pollMemory()
                    memoryHistory.append(MetricPoint(time: Date(), value: mem))
                    trimHistory(&memoryHistory)
                } catch {
                    print("[ShellDeck] Memory poll error: \(error)")
                }

                do {
                    let cpu = try await pollCPU()
                    cpuHistory.append(MetricPoint(time: Date(), value: cpu))
                    trimHistory(&cpuHistory)
                } catch {
                    print("[ShellDeck] CPU poll error: \(error)")
                }

                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        diskUsed = 0
        diskTotal = 0
    }

    // MARK: - Helpers

    private func bufferToString(_ buffer: ByteBuffer) -> String? {
        buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
    }

    // MARK: - Disk

    private func pollDisk() async throws {
        guard let client else { return }
        let output = try await client.executeCommand("df -k /")
        guard let text = bufferToString(output).flatMap({ $0.isEmpty ? nil : $0 }) else {
            throw MonitorError.commandFailed("df 无输出")
        }
        let lines = text.split(separator: "\n")
        guard lines.count >= 2 else { throw MonitorError.commandFailed("df 输出格式错误") }
        let fields = lines[1].split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        guard fields.count >= 4 else { throw MonitorError.commandFailed("df 字段不足") }
        guard let totalKB = Double(fields[1]), let usedKB = Double(fields[2]) else {
            throw MonitorError.commandFailed("df 数值解析失败")
        }
        diskTotal = totalKB / (1024.0 * 1024.0)
        diskUsed = usedKB / (1024.0 * 1024.0)
    }

    // MARK: - Memory

    private func pollMemory() async throws -> Double {
        guard let client else { return 0 }
        let output = try await client.executeCommand("cat /proc/meminfo")
        guard let text = bufferToString(output).flatMap({ $0.isEmpty ? nil : $0 }) else {
            throw MonitorError.commandFailed("meminfo 无输出")
        }
        var memTotal: Double = 0
        var memAvailable: Double = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if line.hasPrefix("MemTotal:"), parts.count >= 2 {
                memTotal = Double(parts[1]) ?? 0
            } else if line.hasPrefix("MemAvailable:"), parts.count >= 2 {
                memAvailable = Double(parts[1]) ?? 0
            }
        }
        guard memTotal > 0 else { throw MonitorError.commandFailed("meminfo 格式错误") }
        return ((memTotal - memAvailable) / memTotal) * 100.0
    }

    // MARK: - CPU

    private func pollCPU() async throws -> Double {
        let stats1 = try await readCpuStats()
        try await Task.sleep(nanoseconds: 200_000_000)
        let stats2 = try await readCpuStats()

        let idleDelta = stats2.idle - stats1.idle
        let totalDelta = stats2.total - stats1.total
        guard totalDelta > 0 else { return 0 }
        return (1.0 - Double(idleDelta) / Double(totalDelta)) * 100.0
    }

    private func readCpuStats() async throws -> (idle: UInt64, total: UInt64) {
        guard let client else { return (0, 0) }
        let output = try await client.executeCommand("cat /proc/stat")
        guard let text = bufferToString(output).flatMap({ $0.isEmpty ? nil : $0 }),
              let firstLine = text.split(separator: "\n").first,
              firstLine.hasPrefix("cpu ") else {
            throw MonitorError.commandFailed("stat 格式错误")
        }
        let vals = firstLine.split(whereSeparator: \.isWhitespace).dropFirst().compactMap { UInt64($0) }
        guard vals.count >= 4 else { throw MonitorError.commandFailed("stat 字段不足") }
        return (vals[3], vals.reduce(0, +))
    }

    // MARK: - Trimming

    private func trimHistory(_ history: inout [MetricPoint]) {
        guard history.count > maxHistory else { return }
        history = Array(history.dropFirst(history.count - maxHistory))
    }
}
