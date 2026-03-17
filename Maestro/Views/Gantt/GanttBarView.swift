import SwiftUI
import MaestroCore

// Gantt bar rendering is handled inline by Swift Charts BarMark in GanttChartView.
// This file contains helper extensions for Gantt-related date formatting.

extension Date {
    var ganttFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    func daysBetween(_ other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: self, to: other).day ?? 0
    }
}
