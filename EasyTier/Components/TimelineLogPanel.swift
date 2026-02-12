import SwiftUI

struct TimelineLogPanel: View {
    let events: [String]
    
    var timelineEntries: [TimelineEntry] {
        TimelineEntry.parse(events)
    }
    
    var body: some View {
        if timelineEntries.isEmpty {
            Text("no_parsed_events")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                    TimelineRow(entry: entry, isLast: index == timelineEntries.count - 1)
                }
            }
        }
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time Column
            VStack(alignment: .trailing, spacing: 2) {
                if let date = entry.date {
                    Text(date, style: .time) // e.g., 2:31 PM
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text(date.formatted(.dateTime.month().day())) // e.g., Jan 4
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("not_available")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.top, 2)
            
            // Timeline Graphic (Dot + Line)
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            
            // JSON Content Bubble
            VStack(alignment: .leading, spacing: 12) {
                if let name = entry.name {
                    Text(name)
                        .font(.headline)
                }
                Text(entry.payload)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.bottom, 24)
        }
    }
}

struct TimelineEntry: Identifiable {
    var id: String { self.original }
    let date: Date?
    let name: String?
    let payload: String
    let original: String
    
    // Parser
    static func parse(_ rawLines: [String]) -> [TimelineEntry] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return rawLines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timeStr = json["time"] as? String,
                  let date = isoFormatter.date(from: timeStr),
                  let eventData = json["event"] else {
                return TimelineEntry(date: nil, name: nil, payload: line, original: line)
            }
            
            let name: String?
            let payload: Any
            if let eventData = eventData as? [String: Any], eventData.count == 1, let name_ = eventData.keys.first, let payload_ = eventData[name_] {
                name = name_
                payload = payload_
            } else {
                name = nil
                payload = eventData
            }
            
            if let prettyData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                return TimelineEntry(date: date, name: name, payload: prettyString, original: line)
            }
            return TimelineEntry(date: date, name: nil, payload: line, original: line)
        }.sorted { $0.date ?? .distantPast > $1.date ?? .distantPast }
    }
}
