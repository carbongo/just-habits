import SwiftUI

struct HabitListView: View {
    let habits: [Habit]
    let selectedDayKey: String
    let engine: HabitStatusEngine
    let parentTitle: (UUID) -> String?
    let onEdit: (Habit) -> Void
    let onDelete: (Habit) -> Void
    let onBlocked: (String) -> Void

    var body: some View {
        List {
            if habits.isEmpty {
                ContentUnavailableView(
                    "No Habits Yet",
                    systemImage: "checklist",
                    description: Text("Create your first habit to start tracking this day.")
                )
            }

            ForEach(habits, id: \.id) { habit in
                HabitRow(
                    habit: habit,
                    selectedDayKey: selectedDayKey,
                    engine: engine,
                    parentTitle: parentTitle,
                    onEdit: { onEdit(habit) },
                    onDelete: { onDelete(habit) },
                    onBlocked: onBlocked
                )
            }
        }
        .navigationTitle(DayKey.label(for: selectedDayKey))
    }
}

private struct HabitRow: View {
    let habit: Habit
    let selectedDayKey: String
    let engine: HabitStatusEngine
    let parentTitle: (UUID) -> String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBlocked: (String) -> Void

    private var status: HabitDayStatus {
        engine.effectiveStatus(habit: habit, day: selectedDayKey)
    }

    private var unlocked: Bool {
        engine.canCompleteChild(habit: habit, day: selectedDayKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.normalizedTitle)
                        .font(.headline)

                    Text(triggerDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 8) {
                switch habit.kind {
                case .achieving:
                    Button("Done") {
                        apply(status: .complete)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!engine.canSetStatus(habit: habit, day: selectedDayKey, status: .complete))

                    Button("Reset") {
                        apply(status: .incomplete)
                    }
                    .buttonStyle(.bordered)
                case .skipping:
                    Button("Did It") {
                        apply(status: .failed)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!engine.canSetStatus(habit: habit, day: selectedDayKey, status: .failed))

                    Button("Reset") {
                        apply(status: .halfComplete)
                    }
                    .buttonStyle(.bordered)
                }

                Menu("Override") {
                    ForEach(HabitDayStatus.allCases) { option in
                        Button(option.title) {
                            apply(status: option)
                        }
                        .disabled(!engine.canSetStatus(habit: habit, day: selectedDayKey, status: option))
                    }
                }
                .menuStyle(.borderedButton)
            }

            if !unlocked {
                Text("Locked until parent chain habit is complete for this day.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch status {
        case .incomplete:
            return .gray
        case .halfComplete:
            return .orange
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }

    private var triggerDescription: String {
        switch habit.trigger {
        case .time(let components):
            return "Time trigger at \(formattedTime(components: components))"
        case .chain(let parentID):
            let parentName = parentTitle(parentID) ?? "Unknown habit"
            return "Chain trigger after \(parentName)"
        }
    }

    private func formattedTime(components: DateComponents) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = 1
        comps.day = 1
        comps.hour = components.hour ?? Habit.defaultTimeComponents.hour
        comps.minute = components.minute ?? Habit.defaultTimeComponents.minute

        let calendar = Calendar.current
        guard let date = calendar.date(from: comps) else {
            return "9:00 AM"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func apply(status: HabitDayStatus) {
        let success = engine.setStatus(
            habit: habit,
            day: selectedDayKey,
            status: status,
            source: .user
        )

        if !success {
            onBlocked("Complete the parent chain habit before setting this status.")
        }
    }
}
