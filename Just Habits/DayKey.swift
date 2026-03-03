import Foundation

enum DayKey {
    static func from(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    static func last14DayKeys(from reference: Date = Date(), calendar: Calendar = .current) -> [String] {
        let start = calendar.startOfDay(for: reference)
        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else {
                return nil
            }
            return from(date, calendar: calendar)
        }
    }

    static func label(for key: String, reference: Date = Date(), calendar: Calendar = .current) -> String {
        if key == from(reference, calendar: calendar) {
            return "Today"
        }

        guard let date = date(from: key, calendar: calendar) else {
            return key
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
