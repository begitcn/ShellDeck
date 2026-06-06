import SwiftUI
import Charts

struct SystemMonitorView: View {
    let monitorService: MonitorService

    @State private var isVisible = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SDSpacing.xl.value) {
                cpuCard
                memoryCard
                diskCard
            }
            .padding(SDSpacing.xl.value)
        }
        .background(Color.sdBackground)
        .onAppear {
            isVisible = true
            monitorService.startMonitoring()
        }
        .onDisappear {
            isVisible = false
            monitorService.stopMonitoring(clearHistory: false)
        }
    }

    // MARK: - CPU

    @ViewBuilder
    private var cpuCard: some View {
        let current = currentCPU
        let maxVal = maxCPU
        let themeColor: Color = current > 80 ? .sdDanger : (current > 60 ? .sdWarning : .sdInfo)

        MonitorCard(title: "CPU 占用率", icon: "cpu", iconColor: themeColor) {
            VStack(alignment: .leading, spacing: 14) {
                if monitorService.cpuHistory.isEmpty {
                    emptyState("等待数据…")
                } else {
                    cpuChart(themeColor: themeColor)
                    cpuStats(current: current, maxVal: maxVal, themeColor: themeColor)
                }
            }
        }
    }

    private func cpuChart(themeColor: Color) -> some View {
        let gradient = LinearGradient(
            gradient: Gradient(colors: [themeColor.opacity(0.3), themeColor.opacity(0.0)]),
            startPoint: .top,
            endPoint: .bottom
        )
        return Chart {
            ForEach(monitorService.cpuHistory) { point in
                AreaMark(
                    x: .value("时间", point.time),
                    y: .value("占用率", point.value)
                )
                .foregroundStyle(gradient)
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", point.time),
                    y: .value("占用率", point.value)
                )
                .foregroundStyle(themeColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.primary.opacity(0.1))
                AxisValueLabel("\(value.as(Int.self)!)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel(format: .dateTime.minute().second())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 160)
    }

    private func cpuStats(current: Double, maxVal: Double, themeColor: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("当前")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(current))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(themeColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("历史最高")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(maxVal))%")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Memory

    @ViewBuilder
    private var memoryCard: some View {
        let current = currentMemory
        let maxVal = maxMemory
        let themeColor: Color = current > 80 ? .sdDanger : (current > 60 ? .sdWarning : .sdSuccess)

        MonitorCard(title: "内存占用率", icon: "memorychip", iconColor: themeColor) {
            VStack(alignment: .leading, spacing: 14) {
                if monitorService.memoryHistory.isEmpty {
                    emptyState("等待数据…")
                } else {
                    memoryChart(themeColor: themeColor)
                    cpuStats(current: current, maxVal: maxVal, themeColor: themeColor)
                }
            }
        }
    }

    private func memoryChart(themeColor: Color) -> some View {
        let gradient = LinearGradient(
            gradient: Gradient(colors: [themeColor.opacity(0.3), themeColor.opacity(0.0)]),
            startPoint: .top,
            endPoint: .bottom
        )
        return Chart {
            ForEach(monitorService.memoryHistory) { point in
                AreaMark(
                    x: .value("时间", point.time),
                    y: .value("占用率", point.value)
                )
                .foregroundStyle(gradient)
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", point.time),
                    y: .value("占用率", point.value)
                )
                .foregroundStyle(themeColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.primary.opacity(0.1))
                AxisValueLabel("\(value.as(Int.self)!)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel(format: .dateTime.minute().second())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 160)
    }

    // MARK: - Disk

    @ViewBuilder
    private var diskCard: some View {
        let percent = diskPercent
        let themeColor: Color = percent > 85 ? .sdDanger : (percent > 70 ? .sdWarning : .accentColor)

        MonitorCard(title: "存储磁盘空间", icon: "internaldrive", iconColor: themeColor) {
            VStack(alignment: .leading, spacing: 16) {
                if monitorService.diskTotal <= 0 {
                    emptyState("等待数据…")
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 40) {
                        diskRing(themeColor: themeColor)
                            .frame(width: 140, height: 140)
                            .padding(.vertical, 8)
                        diskDetails(themeColor: themeColor)
                    }
                }
            }
        }
    }

    private func diskDetails(themeColor: Color) -> some View {
        VStack(spacing: 12) {
            diskDetailRow(label: "总容量", value: "\(diskTotalStr) GB", icon: "square.grid.3x3.fill", color: .secondary)
            Divider()
            diskDetailRow(label: "已使用", value: "\(diskUsedStr) GB", icon: "chart.pie.fill", color: themeColor)
            Divider()
            diskDetailRow(label: "剩余可用", value: "\(diskFreeStr) GB", icon: "square.dashed", color: .sdSuccess)
        }
        .padding(SDSpacing.lg.value)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Disk Ring

    private func diskRing(themeColor: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 14)

            Circle()
                .trim(from: 0, to: diskPercent / 100.0)
                .stroke(
                    themeColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 5)
                .animation(.easeInOut(duration: 0.5), value: diskPercent)

            Circle()
                .trim(from: 0, to: diskPercent / 100.0)
                .stroke(
                    AngularGradient(
                        colors: [themeColor, themeColor.opacity(0.7), themeColor],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: diskPercent)

            VStack(spacing: 2) {
                Text("\(Int(diskPercent))%")
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(themeColor)
                Text("已使用")
                    .font(.caption2)
                    .fontWeight(.semibold)
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
        String(format: "%.1f", max(0.0, monitorService.diskTotal - monitorService.diskUsed))
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 50)
        .frame(maxWidth: .infinity)
    }

    private func diskDetailRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Monitor Card Container

struct MonitorCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: Content

    init(title: String, icon: String, iconColor: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
            }
            content
        }
        .sdCardStyle()
    }
}

#Preview {
    SystemMonitorView(monitorService: MonitorService())
        .frame(width: 700, height: 600)
}
