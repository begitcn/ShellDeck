import SwiftUI
import Charts

struct SystemMonitorView: View {
    let monitorService: MonitorService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    cpuCard
                    memoryCard
                }
                diskCard
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - CPU

    private var cpuCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("CPU 占用率")
                        .font(.headline)
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundStyle(.blue)
                }

                if monitorService.cpuHistory.isEmpty {
                    emptyState("等待数据…")
                } else {
                    Chart {
                        ForEach(monitorService.cpuHistory) { point in
                            AreaMark(
                                x: .value("时间", point.time),
                                y: .value("占用率", point.value)
                            )
                            .foregroundStyle(.blue.opacity(0.15))
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value("时间", point.time),
                                y: .value("占用率", point.value)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel("\(value.as(Int.self)!)%")
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .second, count: 5)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: Date.FormatStyle(time: .shortened))
                        }
                    }
                    .frame(height: 180)

                    HStack {
                        Text("当前")
                            .foregroundStyle(.secondary)
                        Text("\(Int(currentCPU))%")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(currentCPU > 80 ? .red : .blue)
                        Spacer()
                        Text("历史最高: \(Int(maxCPU))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
    }

    // MARK: - Memory

    private var memoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("内存占用率")
                        .font(.headline)
                } icon: {
                    Image(systemName: "memorychip")
                        .foregroundStyle(.green)
                }

                if monitorService.memoryHistory.isEmpty {
                    emptyState("等待数据…")
                } else {
                    Chart {
                        ForEach(monitorService.memoryHistory) { point in
                            AreaMark(
                                x: .value("时间", point.time),
                                y: .value("占用率", point.value)
                            )
                            .foregroundStyle(.green.opacity(0.15))
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value("时间", point.time),
                                y: .value("占用率", point.value)
                            )
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel("\(value.as(Int.self)!)%")
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .second, count: 5)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: Date.FormatStyle(time: .shortened))
                        }
                    }
                    .frame(height: 180)

                    HStack {
                        Text("当前")
                            .foregroundStyle(.secondary)
                        Text("\(Int(currentMemory))%")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(currentMemory > 80 ? .red : .green)
                        Spacer()
                        Text("历史最高: \(Int(maxMemory))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
    }

    // MARK: - Disk

    private var diskCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label {
                    Text("磁盘占用")
                        .font(.headline)
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.orange)
                }

                if monitorService.diskTotal <= 0 {
                    emptyState("等待数据…")
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 32) {
                        diskRing
                            .frame(width: 120, height: 120)

                        VStack(alignment: .leading, spacing: 10) {
                            detailRow(label: "总容量", value: "\(diskTotalStr) GB", color: .secondary)
                            detailRow(label: "已用", value: "\(diskUsedStr) GB", color: .orange)
                            detailRow(label: "可用", value: "\(diskFreeStr) GB", color: .green)
                            detailRow(label: "占用率", value: "\(Int(diskPercent))%", color: .orange)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Disk Ring

    private var diskRing: some View {
        ZStack {
            Circle()
                .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 12)

            Circle()
                .trim(from: 0, to: diskPercent / 100.0)
                .stroke(
                    AngularGradient(
                        colors: [.orange, .yellow, .orange],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: diskPercent)

            VStack(spacing: 2) {
                Text("\(Int(diskPercent))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text("已用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var currentCPU: Double {
        monitorService.cpuHistory.last?.value ?? 0
    }

    private var maxCPU: Double {
        monitorService.cpuHistory.map(\.value).max() ?? 0
    }

    private var currentMemory: Double {
        monitorService.memoryHistory.last?.value ?? 0
    }

    private var maxMemory: Double {
        monitorService.memoryHistory.map(\.value).max() ?? 0
    }

    private var diskPercent: Double {
        guard monitorService.diskTotal > 0 else { return 0 }
        return (monitorService.diskUsed / monitorService.diskTotal) * 100.0
    }

    private var diskUsedStr: String {
        String(format: "%.1f", monitorService.diskUsed)
    }

    private var diskTotalStr: String {
        String(format: "%.1f", monitorService.diskTotal)
    }

    private var diskFreeStr: String {
        String(format: "%.1f", monitorService.diskTotal - monitorService.diskUsed)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private func detailRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

#Preview {
    SystemMonitorView(monitorService: MonitorService())
        .frame(width: 600, height: 500)
}
