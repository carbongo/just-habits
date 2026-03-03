import Foundation
import SwiftData

enum HabitKind: String, Codable, CaseIterable, Identifiable {
    case achieving
    case skipping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .achieving:
            return "Achieving"
        case .skipping:
            return "Skipping"
        }
    }
}

enum TriggerMode: String, CaseIterable, Identifiable {
    case time
    case chain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time:
            return "Time"
        case .chain:
            return "Chain"
        }
    }
}

enum HabitTrigger: Codable, Equatable {
    case time(DateComponents)
    case chain(UUID)

    private enum CodingKeys: String, CodingKey {
        case type
        case hour
        case minute
        case parentHabitID
    }

    private enum TriggerType: String, Codable {
        case time
        case chain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TriggerType.self, forKey: .type)

        switch type {
        case .time:
            let hour = try container.decodeIfPresent(Int.self, forKey: .hour)
            let minute = try container.decodeIfPresent(Int.self, forKey: .minute)
            self = .time(DateComponents(hour: hour, minute: minute))
        case .chain:
            let parentHabitID = try container.decode(UUID.self, forKey: .parentHabitID)
            self = .chain(parentHabitID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .time(let components):
            try container.encode(TriggerType.time, forKey: .type)
            try container.encodeIfPresent(components.hour, forKey: .hour)
            try container.encodeIfPresent(components.minute, forKey: .minute)
        case .chain(let parentHabitID):
            try container.encode(TriggerType.chain, forKey: .type)
            try container.encode(parentHabitID, forKey: .parentHabitID)
        }
    }
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var triggerModeRaw: String
    var triggerHour: Int?
    var triggerMinute: Int?
    var chainParentHabitID: UUID?
    var createdAt: Date
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        kind: HabitKind,
        trigger: HabitTrigger,
        createdAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.triggerModeRaw = TriggerMode.time.rawValue
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.triggerHour = Habit.defaultTimeComponents.hour
        self.triggerMinute = Habit.defaultTimeComponents.minute
        self.chainParentHabitID = nil
        self.trigger = trigger
    }

    var kind: HabitKind {
        get { HabitKind(rawValue: kindRaw) ?? .achieving }
        set { kindRaw = newValue.rawValue }
    }

    var triggerMode: TriggerMode {
        get { TriggerMode(rawValue: triggerModeRaw) ?? .time }
        set { triggerModeRaw = newValue.rawValue }
    }

    var trigger: HabitTrigger {
        get {
            switch triggerMode {
            case .time:
                return .time(DateComponents(hour: triggerHour, minute: triggerMinute))
            case .chain:
                guard let parentID = chainParentHabitID else {
                    return .time(Self.defaultTimeComponents)
                }
                return .chain(parentID)
            }
        }
        set {
            switch newValue {
            case .time(let components):
                triggerMode = .time
                triggerHour = components.hour
                triggerMinute = components.minute
                chainParentHabitID = nil
            case .chain(let parentID):
                triggerMode = .chain
                chainParentHabitID = parentID
                triggerHour = nil
                triggerMinute = nil
            }
        }
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var dueTimeComponents: DateComponents {
        switch trigger {
        case .time(let components):
            return DateComponents(hour: components.hour ?? Self.defaultTimeComponents.hour,
                                  minute: components.minute ?? Self.defaultTimeComponents.minute)
        case .chain:
            return Self.defaultTimeComponents
        }
    }

    func sortTuple() -> (Int, Int, Int, String) {
        switch trigger {
        case .time(let components):
            return (0, components.hour ?? 99, components.minute ?? 99, normalizedTitle.lowercased())
        case .chain:
            return (1, 99, 99, normalizedTitle.lowercased())
        }
    }

    static let defaultTimeComponents = DateComponents(hour: 9, minute: 0)
}
