import Foundation
import RatioCore

/// A frozen, explicitly fictional fixture for reproducing the reference at native size.
/// Only --reference-demo selects this dataset; it never enters the real ledger.
enum ReferenceDemo {
    static let activeSource = ActivitySource(id: "demo.reference.terminal", name: "Terminal")
    private static let sources = [
        activeSource,
        ActivitySource(id: "demo.reference.youtube", name: "YouTube", kind: .website),
        ActivitySource(id: "demo.reference.stripe", name: "Stripe", kind: .website),
        ActivitySource(id: "demo.reference.cursor", name: "Cursor")
    ]
    static var sourceOrder: [String] { sources.map(\.id) }
    static func ledger(day: String) -> ActivityLedger {
        var ledger = ActivityLedger()
        let seconds: [Double] = [18, 2, 1, 3]
        for (index, source) in sources.enumerated() {
            ledger.record(seconds: seconds[index], source: source, day: day)
            if index == 0 || index == 3 { ledger.classify(source, as: .create) }
        }
        return ledger
    }
}
