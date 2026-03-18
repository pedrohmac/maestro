import Foundation

extension Date {
    public var relativeFormatted: String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 60 {
            return "less than a minute ago"
        }
        let minutes = seconds / 60
        if minutes == 1 {
            return "1 minute ago"
        }
        if minutes < 60 {
            return "\(minutes) minutes ago"
        }
        let hours = minutes / 60
        if hours == 1 {
            return "1 hour ago"
        }
        if hours < 24 {
            return "\(hours) hours ago"
        }
        let days = hours / 24
        if days == 1 {
            return "1 day ago"
        }
        return "\(days) days ago"
    }
}
