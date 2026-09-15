import Foundation

/// A deterministic foreground observation, supplied by the native operating-system adapter.
public struct ActivityObservation {
    public var date: Date
    public var uptime: TimeInterval
    public var idleSeconds: TimeInterval
    public var source: ActivitySource?

    public init(date: Date, uptime: TimeInterval, idleSeconds: TimeInterval, source: ActivitySource?) {
        self.date = date
        self.uptime = uptime
        self.idleSeconds = idleSeconds
        self.source = source
    }
}
