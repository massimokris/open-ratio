import Foundation

extension ActivityLedger {
    /// Exports retained days using remembered categories at the time of export.
    /// Text follows RFC 4180 escaping; seconds always use a locale-independent decimal point.
    public func activityCSV() -> String {
        var rows = ["date,source_type,source_id,name,category,seconds"]
        for day in history {
            for activity in day.activities.sorted(by: { $0.source.id < $1.source.id }) {
                let fields = [day.day, activity.source.kind.rawValue, activity.source.id,
                              activity.source.name, activity.category?.rawValue ?? "unclassified",
                              String(activity.seconds)]
                rows.append(fields.map(Self.csvField).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: ",\"\r\n")) != nil else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
