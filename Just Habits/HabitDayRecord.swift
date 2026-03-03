import Foundation
import SwiftData

enum HabitDayStatus: String, Codable, CaseIterable, Identifiable {
    case incomplete
    case halfComplete
    case complete
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incomplete:
            return "Incomplete"
        case .halfComplete:
            return "Half Complete"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }
}

enum StatusSource: String, Codable {
    case auto
    case user
}

@Model
final class HabitDayRecord {
    @Attribute(.unique) var recordKey: String
    var habitID: UUID
    var dayKey: String
    var statusRaw: String
    var sourceRaw: String
    var updatedAt: Date

    init(
        habitID: UUID,
        dayKey: String,
        status: HabitDayStatus,
        source: StatusSource,
        updatedAt: Date = Date()
    ) {
        self.habitID = habitID
        self.dayKey = dayKey
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.updatedAt = updatedAt
        self.recordKey = HabitDayRecord.key(habitID: habitID, dayKey: dayKey)
    }

    var status: HabitDayStatus {
        get { HabitDayStatus(rawValue: statusRaw) ?? .incomplete }
        set { statusRaw = newValue.rawValue }
    }

    var source: StatusSource {
        get { StatusSource(rawValue: sourceRaw) ?? .auto }
        set { sourceRaw = newValue.rawValue }
    }

    static func key(habitID: UUID, dayKey: String) -> String {
        "\(habitID.uuidString)|\(dayKey)"
    }
}
