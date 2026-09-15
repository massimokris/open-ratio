import Foundation

/// The local persistence boundary for real activity. Demo ledgers stay in memory.
public struct ActivityStore {
    public struct LoadResult {
        public var ledger: ActivityLedger
        public var notice: String?
    }

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("activity.json") }
    public var backupURL: URL { directory.appendingPathComponent("activity-backup.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func load() throws -> LoadResult {
        let current: Data
        do {
            current = try Data(contentsOf: fileURL)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    do {
                        let backup = try Data(contentsOf: backupURL)
                        let envelope = try decode(backup, at: backupURL)
                        try backup.write(to: fileURL, options: .atomic)
                        return LoadResult(ledger: envelope.ledger, notice: "Recovered missing activity from the last valid backup at \(backupURL.path).")
                    } catch let error as StoreError {
                        throw error
                    } catch {
                        throw StoreError.fileOperation("Unable to recover activity from its backup; the backup has been left unchanged", backupURL, error)
                    }
                }
                return LoadResult(ledger: ActivityLedger(), notice: nil)
            }
            throw StoreError.fileOperation("Unable to read activity; the original has been left unchanged", fileURL, error)
        }
        do {
            let envelope = try decode(current, at: fileURL)
            return LoadResult(ledger: envelope.ledger, notice: nil)
        } catch let error as StoreError {
            throw error
        } catch {
            let preservedURL = directory.appendingPathComponent("activity-corrupt-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: fileURL, to: preservedURL)
            } catch {
                throw StoreError.fileOperation("Unable to preserve unreadable activity; the original has been left unchanged", fileURL, error)
            }
            do {
                guard FileManager.default.fileExists(atPath: backupURL.path) else {
                    let empty = ActivityLedger()
                    let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, ledger: empty))
                    try data.write(to: fileURL, options: .atomic)
                    return LoadResult(ledger: empty, notice: "Started with empty activity because no valid backup was available. The unreadable original is retained at \(preservedURL.path).")
                }
                let backup = try Data(contentsOf: backupURL)
                let envelope = try decode(backup, at: backupURL)
                try backup.write(to: fileURL, options: .atomic)
                return LoadResult(ledger: envelope.ledger, notice: "Recovered activity from the last valid backup. The unreadable original is retained at \(preservedURL.path).")
            } catch let error as StoreError {
                throw error
            } catch {
                throw StoreError.fileOperation("Unable to recover activity from its backup. The unreadable original is retained at \(preservedURL.path)", directory, error)
            }
        }
    }

    public func save(_ ledger: ActivityLedger) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, ledger: ledger))
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let previous = try Data(contentsOf: fileURL)
                _ = try decode(previous, at: fileURL)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    do {
                        _ = try decode(Data(contentsOf: backupURL), at: backupURL)
                    } catch let error as StoreError {
                        throw error
                    } catch {
                        throw StoreError.fileOperation("Unable to replace unreadable activity backup; the file has been left unchanged", backupURL, error)
                    }
                }
                try previous.write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.fileOperation("Unable to save activity", directory, error)
        }
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var ledger: ActivityLedger
    }

    private struct Header: Decodable {
        var schemaVersion: Int
    }

    private func decode(_ data: Data, at url: URL) throws -> Envelope {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion == 1 else {
            throw StoreError.unsupportedSchema(header.schemaVersion, url)
        }
        let envelope = try decoder.decode(Envelope.self, from: data)
        let ledger = envelope.ledger
        guard ledger.sources.allSatisfy({ !$0.key.isEmpty && $0.key == $0.value.id }),
              ledger.categories.keys.allSatisfy({ ledger.sources[$0] != nil }),
              ledger.days.values.allSatisfy({ totals in
                  totals.allSatisfy { sourceID, seconds in
                      ledger.sources[sourceID] != nil && seconds.isFinite && seconds >= 0
                  }
              }) else { throw CocoaError(.coderReadCorrupt) }
        return envelope
    }

    private enum StoreError: LocalizedError {
        case unsupportedSchema(Int, URL)
        case fileOperation(String, URL, Error)

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version, url):
                return "Activity at \(url.path) uses unsupported schema \(version). Open it with a newer compatible version of Open Ratio. The file has been left unchanged."
            case let .fileOperation(operation, url, underlying):
                return "\(operation) at \(url.path). \(underlying.localizedDescription) Check access to the data folder."
            }
        }
    }
}
