import SwiftUI

struct DaySidebarView: View {
    let dayKeys: [String]
    @Binding var selection: String
    private static let sidebarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    var body: some View {
        List(dayKeys, id: \.self, selection: $selection) { dayKey in
            HStack {
                if let date = DayKey.date(from: dayKey) {
                    Text(Self.sidebarDateFormatter.string(from: date))
                } else {
                    Text(dayKey)
                }
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
