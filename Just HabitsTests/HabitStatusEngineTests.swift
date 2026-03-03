import Foundation
import SwiftData
import XCTest
@testable import Just_Habits

@MainActor
final class HabitStatusEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var engine: HabitStatusEngine!
    private var calendar: Calendar!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        defaultsSuiteName = "HabitStatusEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)

        let schema = Schema([
            Habit.self,
            HabitDayRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        engine = HabitStatusEngine(modelContext: context, calendar: calendar, defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        engine = nil
        context = nil
        container = nil
        calendar = nil
    }

    func testAchievingDefaultIsIncomplete() throws {
        let habit = makeHabit(kind: .achieving)
        let day = DayKey.from(Date(), calendar: calendar)

        engine.ensureRecords(for: [habit], day: day)

        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: day), .incomplete)
    }

    func testAchievingRemainsIncompleteAfterRolloverIfUntouched() throws {
        let habit = makeHabit(kind: .achieving)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayKey = DayKey.from(yesterday, calendar: calendar)
        let todayKey = DayKey.from(Date(), calendar: calendar)

        engine.ensureRecords(for: [habit], day: yesterdayKey)
        engine.rolloverIfNeeded(now: Date())

        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: yesterdayKey), .incomplete)
        XCTAssertEqual(defaults.string(forKey: "HabitStatusEngine.lastRolloverDayKey"), todayKey)
    }

    func testSkippingDefaultIsHalfComplete() throws {
        let habit = makeHabit(kind: .skipping)
        let day = DayKey.from(Date(), calendar: calendar)

        engine.ensureRecords(for: [habit], day: day)

        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: day), .halfComplete)
    }

    func testSkippingMarkedDoneBecomesFailed() throws {
        let habit = makeHabit(kind: .skipping)
        let day = DayKey.from(Date(), calendar: calendar)

        engine.ensureRecords(for: [habit], day: day)
        let success = engine.setStatus(habit: habit, day: day, status: .failed, source: .user)

        XCTAssertTrue(success)
        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: day), .failed)
    }

    func testSkippingUntouchedBecomesCompleteAfterRollover() throws {
        let habit = makeHabit(kind: .skipping)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayKey = DayKey.from(yesterday, calendar: calendar)

        engine.ensureRecords(for: [habit], day: yesterdayKey)
        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: yesterdayKey), .halfComplete)

        engine.rolloverIfNeeded(now: Date())

        XCTAssertEqual(engine.effectiveStatus(habit: habit, day: yesterdayKey), .complete)
    }

    func testChainBlocksChildCompletionWhenParentIncomplete() throws {
        let parent = makeHabit(kind: .achieving)
        let child = Habit(
            title: "Child",
            kind: .achieving,
            trigger: .chain(parent.id)
        )
        context.insert(child)

        let day = DayKey.from(Date(), calendar: calendar)
        engine.ensureRecords(for: [parent, child], day: day)

        let success = engine.setStatus(habit: child, day: day, status: .complete, source: .user)

        XCTAssertFalse(success)
        XCTAssertEqual(engine.effectiveStatus(habit: child, day: day), .incomplete)
    }

    func testChainAllowsChildAfterParentCompleteOnSameDay() throws {
        let parent = makeHabit(kind: .achieving)
        let child = Habit(
            title: "Child",
            kind: .achieving,
            trigger: .chain(parent.id)
        )
        context.insert(child)

        let day = DayKey.from(Date(), calendar: calendar)
        engine.ensureRecords(for: [parent, child], day: day)

        XCTAssertTrue(engine.setStatus(habit: parent, day: day, status: .complete, source: .user))
        XCTAssertTrue(engine.setStatus(habit: child, day: day, status: .complete, source: .user))
        XCTAssertEqual(engine.effectiveStatus(habit: child, day: day), .complete)
    }

    func testHistoricalEditStillEnforcesChain() throws {
        let parent = makeHabit(kind: .achieving)
        let child = Habit(
            title: "Child",
            kind: .achieving,
            trigger: .chain(parent.id)
        )
        context.insert(child)

        let historicalDate = calendar.date(byAdding: .day, value: -7, to: Date())!
        let historicalDay = DayKey.from(historicalDate, calendar: calendar)

        engine.ensureRecords(for: [parent, child], day: historicalDay)

        XCTAssertFalse(engine.setStatus(habit: child, day: historicalDay, status: .complete, source: .user))
        XCTAssertTrue(engine.setStatus(habit: parent, day: historicalDay, status: .complete, source: .user))
        XCTAssertTrue(engine.setStatus(habit: child, day: historicalDay, status: .complete, source: .user))
    }

    func testDayKeyGenerationStableAcrossMidnightBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let beforeMidnight = try XCTUnwrap(formatter.date(from: "2026-03-03T23:59:59Z"))
        let afterMidnight = try XCTUnwrap(formatter.date(from: "2026-03-04T00:00:01Z"))

        let beforeKey = DayKey.from(beforeMidnight, calendar: calendar)
        let afterKey = DayKey.from(afterMidnight, calendar: calendar)

        XCTAssertEqual(beforeKey, "2026-03-03")
        XCTAssertEqual(afterKey, "2026-03-04")
        XCTAssertNotEqual(beforeKey, afterKey)

        let reconstructed = DayKey.date(from: beforeKey, calendar: calendar)
        XCTAssertEqual(DayKey.from(reconstructed ?? beforeMidnight, calendar: calendar), beforeKey)
    }

    @discardableResult
    private func makeHabit(kind: HabitKind) -> Habit {
        let habit = Habit(
            title: "Habit \(UUID().uuidString)",
            kind: kind,
            trigger: .time(DateComponents(hour: 9, minute: 0))
        )
        context.insert(habit)
        return habit
    }
}
