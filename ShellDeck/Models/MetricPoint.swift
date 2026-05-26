import Foundation

struct MetricPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}
