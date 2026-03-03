import Combine
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Habit.title) private var allHabits: [Habit]

    @State private var selectedDayKey = DayKey.from(Date())
    @State private var now = Date()
    @State private var showingEditor = false
    @State private var editingHabitID: UUID?
    @State private var alertMessage: String?

    private let maintenanceTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var engine: HabitStatusEngine {
        HabitStatusEngine(modelContext: modelContext)
    }

    private var activeHabits: [Habit] {
        allHabits.filter { $0.archivedAt == nil }
    }

    private var sortedHabits: [Habit] {
        activeHabits.sorted { lhs, rhs in
            lhs.sortTuple() < rhs.sortTuple()
        }
    }

    private var visibleDayKeys: [String] {
        DayKey.last14DayKeys(from: now)
    }

    private var editingHabit: Habit? {
        guard let editingHabitID else {
            return nil
        }
        return activeHabits.first(where: { $0.id == editingHabitID })
    }

    var body: some View {
        NavigationSplitView {
            DaySidebarView(dayKeys: visibleDayKeys, selection: $selectedDayKey)
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
        } detail: {
            HabitListView(
                habits: sortedHabits,
                selectedDayKey: selectedDayKey,
                engine: engine,
                parentTitle: parentTitle(for:),
                onEdit: editHabit,
                onDelete: deleteHabit,
                onBlocked: { alertMessage = $0 }
            )
        }
        .toolbar {
            ToolbarItem {
                Button {
                    editingHabitID = nil
                    showingEditor = true
                } label: {
                    Label("Add Habit", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            HabitEditorView(
                habits: activeHabits,
                habitToEdit: editingHabit,
                cycleCheck: { parentID in
                    engine.wouldIntroduceCycle(editing: editingHabit, proposedParentID: parentID)
                },
                onSave: saveHabit,
                onCancel: {
                    editingHabitID = nil
                    showingEditor = false
                }
            )
        }
        .alert(
            "Action Blocked",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { alertMessage = nil }
            },
            message: {
                Text(alertMessage ?? "")
            }
        )
        .onAppear {
            runMaintenance(now: Date())
        }
        .onChange(of: selectedDayKey) { _, _ in
            ensureSelectionInRange()
            engine.ensureRecords(for: activeHabits, day: selectedDayKey)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runMaintenance(now: Date())
            }
        }
        .onChange(of: allHabits.map(\.id)) { _, _ in
            engine.ensureRecords(for: activeHabits, day: selectedDayKey)
        }
        .onReceive(maintenanceTimer) { tick in
            runMaintenance(now: tick)
        }
    }

    private func parentTitle(for id: UUID) -> String? {
        activeHabits.first(where: { $0.id == id })?.normalizedTitle
    }

    private func editHabit(_ habit: Habit) {
        editingHabitID = habit.id
        showingEditor = true
    }

    private func deleteHabit(_ habit: Habit) {
        engine.deleteHabit(habit)
        runMaintenance(now: Date())
    }

    private func saveHabit(_ draft: HabitDraft) {
        let habit: Habit

        if let existing = editingHabit {
            habit = existing
        } else {
            habit = Habit(
                title: draft.title,
                kind: draft.kind,
                trigger: draft.trigger
            )
            modelContext.insert(habit)
        }

        if case .chain(let parentID) = draft.trigger,
           engine.wouldIntroduceCycle(editing: habit, proposedParentID: parentID) {
            alertMessage = "This parent selection creates a cycle. Pick a different parent habit."
            return
        }

        habit.title = draft.title
        habit.kind = draft.kind
        habit.trigger = draft.trigger

        do {
            try modelContext.save()
            engine.ensureRecords(for: [habit], day: selectedDayKey)
            editingHabitID = nil
            showingEditor = false
        } catch {
            alertMessage = "Unable to save habit changes."
        }
    }

    private func runMaintenance(now current: Date) {
        now = current
        engine.rolloverIfNeeded(now: current)
        ensureSelectionInRange()
        engine.ensureRecords(for: activeHabits, day: selectedDayKey)
    }

    private func ensureSelectionInRange() {
        let validKeys = visibleDayKeys
        if !validKeys.contains(selectedDayKey), let today = validKeys.first {
            selectedDayKey = today
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Habit.self, HabitDayRecord.self], inMemory: true)
}
