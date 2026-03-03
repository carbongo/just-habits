import SwiftUI

struct HabitDraft {
    var title: String
    var kind: HabitKind
    var trigger: HabitTrigger
}

struct HabitEditorView: View {
    let habits: [Habit]
    let habitToEdit: Habit?
    let cycleCheck: (UUID?) -> Bool
    let onSave: (HabitDraft) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var kind: HabitKind = .achieving
    @State private var triggerMode: TriggerMode = .time
    @State private var dueTime: Date = Date()
    @State private var parentHabitID: UUID?
    @State private var hasLoaded = false

    private var availableParents: [Habit] {
        habits
            .filter { $0.id != habitToEdit?.id }
            .sorted { $0.normalizedTitle.localizedCaseInsensitiveCompare($1.normalizedTitle) == .orderedAscending }
    }

    private var isCycleSelection: Bool {
        triggerMode == .chain && cycleCheck(parentHabitID)
    }

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasChainParent = triggerMode == .time || parentHabitID != nil
        return hasTitle && hasChainParent && !isCycleSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                TextField("Habit title", text: $title)

                Picker("Kind", selection: $kind) {
                    ForEach(HabitKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Picker("Trigger", selection: $triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if triggerMode == .time {
                    DatePicker(
                        "Due Time",
                        selection: $dueTime,
                        displayedComponents: .hourAndMinute
                    )
                } else {
                    Picker("Parent Habit", selection: $parentHabitID) {
                        Text("Select parent")
                            .tag(Optional<UUID>.none)

                        ForEach(availableParents, id: \.id) { habit in
                            Text(habit.normalizedTitle)
                                .tag(Optional(habit.id))
                        }
                    }

                    if isCycleSelection {
                        Text("This chain parent would create a cycle. Pick a different parent.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }

                Button(habitToEdit == nil ? "Create" : "Save") {
                    let trigger: HabitTrigger
                    if triggerMode == .chain, let parentHabitID {
                        trigger = .chain(parentHabitID)
                    } else {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: dueTime)
                        trigger = .time(DateComponents(hour: components.hour, minute: components.minute))
                    }

                    let draft = HabitDraft(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: kind,
                        trigger: trigger
                    )
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 300)
        .onAppear(perform: loadInitialState)
    }

    private func loadInitialState() {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true

        guard let habitToEdit else {
            title = ""
            kind = .achieving
            triggerMode = .time
            dueTime = dateFromTimeComponents(Habit.defaultTimeComponents)
            parentHabitID = nil
            return
        }

        title = habitToEdit.normalizedTitle
        kind = habitToEdit.kind

        switch habitToEdit.trigger {
        case .time(let components):
            triggerMode = .time
            dueTime = dateFromTimeComponents(components)
            parentHabitID = nil
        case .chain(let parentID):
            triggerMode = .chain
            parentHabitID = parentID
            dueTime = dateFromTimeComponents(Habit.defaultTimeComponents)
        }
    }

    private func dateFromTimeComponents(_ components: DateComponents) -> Date {
        var merged = DateComponents()
        merged.year = 2000
        merged.month = 1
        merged.day = 1
        merged.hour = components.hour ?? Habit.defaultTimeComponents.hour
        merged.minute = components.minute ?? Habit.defaultTimeComponents.minute
        return Calendar.current.date(from: merged) ?? Date()
    }
}
