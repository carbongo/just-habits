import Foundation
import SwiftData

@MainActor
struct HabitStatusEngine {
    let modelContext: ModelContext
    var calendar: Calendar = .current
    var defaults: UserDefaults = .standard

    private let rolloverDayKeyStorage = "HabitStatusEngine.lastRolloverDayKey"

    func recordFor(habit: Habit, day dayKey: String) -> HabitDayRecord {
        if let existing = fetchRecord(habitID: habit.id, dayKey: dayKey) {
            return existing
        }

        let record = HabitDayRecord(
            habitID: habit.id,
            dayKey: dayKey,
            status: defaultStatus(for: habit.kind),
            source: .auto
        )
        modelContext.insert(record)
        saveIfNeeded()
        return record
    }

    @discardableResult
    func setStatus(
        habit: Habit,
        day dayKey: String,
        status: HabitDayStatus,
        source: StatusSource = .user
    ) -> Bool {
        guard canSetStatus(habit: habit, day: dayKey, status: status) else {
            return false
        }

        let record = recordFor(habit: habit, day: dayKey)
        record.status = status
        record.source = source
        record.updatedAt = Date()
        saveIfNeeded()
        return true
    }

    func effectiveStatus(habit: Habit, day dayKey: String, now: Date = Date()) -> HabitDayStatus {
        effectiveStatus(habit: habit, day: dayKey, now: now, visited: [])
    }

    func rolloverIfNeeded(now: Date = Date()) {
        let todayKey = DayKey.from(now, calendar: calendar)
        let lastKey = defaults.string(forKey: rolloverDayKeyStorage)
        guard lastKey != todayKey else {
            return
        }

        let halfComplete = HabitDayStatus.halfComplete.rawValue
        let autoSource = StatusSource.auto.rawValue
        let descriptor = FetchDescriptor<HabitDayRecord>(
            predicate: #Predicate { record in
                record.statusRaw == halfComplete && record.sourceRaw == autoSource
            }
        )

        if let records = try? modelContext.fetch(descriptor) {
            for record in records where record.dayKey < todayKey {
                record.status = .complete
                record.source = .auto
                record.updatedAt = now
            }
            saveIfNeeded()
        }

        defaults.set(todayKey, forKey: rolloverDayKeyStorage)
    }

    func canCompleteChild(habit: Habit, day dayKey: String) -> Bool {
        canCompleteChild(habit: habit, day: dayKey, visited: [])
    }

    func canSetStatus(habit: Habit, day dayKey: String, status: HabitDayStatus) -> Bool {
        if requiresParentCompletion(habit: habit, status: status) {
            return canCompleteChild(habit: habit, day: dayKey)
        }
        return true
    }

    func ensureRecords(for habits: [Habit], day dayKey: String) {
        for habit in habits {
            _ = recordFor(habit: habit, day: dayKey)
        }
    }

    func wouldIntroduceCycle(editing habit: Habit?, proposedParentID: UUID?) -> Bool {
        guard let proposedParentID else {
            return false
        }

        guard let habit else {
            return false
        }

        var cursor: UUID? = proposedParentID
        var seen: Set<UUID> = []

        while let current = cursor {
            if current == habit.id {
                return true
            }

            if seen.contains(current) {
                return true
            }
            seen.insert(current)

            guard let node = fetchHabit(id: current) else {
                return false
            }

            switch node.trigger {
            case .time:
                cursor = nil
            case .chain(let parentID):
                cursor = parentID
            }
        }

        return false
    }

    func deleteHabit(_ habit: Habit) {
        let habitID = habit.id

        if let habits = try? modelContext.fetch(FetchDescriptor<Habit>()) {
            for child in habits {
                guard child.id != habitID else { continue }
                if case .chain(let parentID) = child.trigger, parentID == habitID {
                    child.trigger = .time(Habit.defaultTimeComponents)
                }
            }
        }

        let descriptor = FetchDescriptor<HabitDayRecord>(
            predicate: #Predicate { record in
                record.habitID == habitID
            }
        )

        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
        }

        modelContext.delete(habit)
        saveIfNeeded()
    }

    private func effectiveStatus(habit: Habit, day dayKey: String, now: Date, visited: Set<UUID>) -> HabitDayStatus {
        if visited.contains(habit.id) {
            return defaultStatus(for: habit.kind)
        }

        let baseStatus = fetchRecord(habitID: habit.id, dayKey: dayKey)?.status ?? defaultStatus(for: habit.kind)
        guard requiresParentCompletion(habit: habit, status: baseStatus) else {
            return baseStatus
        }

        let canProceed = canCompleteChild(habit: habit, day: dayKey, visited: visited)
        return canProceed ? baseStatus : defaultStatus(for: habit.kind)
    }

    private func canCompleteChild(habit: Habit, day dayKey: String, visited: Set<UUID>) -> Bool {
        guard !visited.contains(habit.id) else {
            return false
        }

        switch habit.trigger {
        case .time:
            return true
        case .chain(let parentHabitID):
            guard let parent = fetchHabit(id: parentHabitID) else {
                return false
            }
            let nextVisited = visited.union([habit.id])
            let parentStatus = effectiveStatus(habit: parent, day: dayKey, now: Date(), visited: nextVisited)
            return parentStatus == .complete
        }
    }

    private func requiresParentCompletion(habit: Habit, status: HabitDayStatus) -> Bool {
        switch habit.kind {
        case .achieving:
            return status == .complete
        case .skipping:
            return status == .complete || status == .failed
        }
    }

    private func defaultStatus(for kind: HabitKind) -> HabitDayStatus {
        switch kind {
        case .achieving:
            return .incomplete
        case .skipping:
            return .halfComplete
        }
    }

    private func fetchRecord(habitID: UUID, dayKey: String) -> HabitDayRecord? {
        let descriptor = FetchDescriptor<HabitDayRecord>(
            predicate: #Predicate { record in
                record.habitID == habitID && record.dayKey == dayKey
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchHabit(id: UUID) -> Habit? {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { habit in
                habit.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func saveIfNeeded() {
        guard modelContext.hasChanges else {
            return
        }
        try? modelContext.save()
    }
}
