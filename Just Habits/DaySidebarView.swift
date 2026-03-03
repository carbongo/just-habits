import SwiftUI

struct DaySidebarView: View {
    let dayKeys: [String]
    @Binding var selection: String

    var body: some View {
        List(dayKeys, id: \.self, selection: $selection) { dayKey in
            HStack {
                Text(DayKey.label(for: dayKey))
                Spacer()
                if dayKey == DayKey.from(Date()) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(dayKey)
        }
        .navigationTitle("Last 14 Days")
    }
}
