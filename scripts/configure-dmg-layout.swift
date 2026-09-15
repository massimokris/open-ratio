#!/usr/bin/env swift

import Darwin
import Foundation

// Finder's on-disk format is undocumented by Apple. This deliberately writes
// only the six records needed by this installer, in one bounded B-tree leaf.
// Format references (no third-party code or runtime dependencies):
// https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod
// https://github.com/dmgbuild/ds_store/blob/master/src/ds_store/buddy.py
// https://github.com/dmgbuild/dmgbuild/blob/main/src/dmgbuild/core.py

private struct LayoutError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    mutating func appendCode(_ value: String) {
        append(contentsOf: value.utf8)
    }
}

private struct FinderRecord {
    let filename: String
    let property: String
    let type: String
    let value: Data

    func encoded() -> Data {
        var result = Data()
        result.appendInteger(UInt32(filename.utf16.count))
        for character in filename.utf16 {
            result.appendInteger(character)
        }
        result.appendCode(property)
        result.appendCode(type)
        if type == "blob" {
            result.appendInteger(UInt32(value.count))
        }
        result.append(value)
        return result
    }

    static func plist(_ property: String, _ values: [String: Any]) throws -> FinderRecord {
        FinderRecord(
            filename: ".", property: property, type: "blob",
            value: try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        )
    }

    static func icon(_ filename: String, x: UInt32, y: UInt32) -> FinderRecord {
        var position = Data()
        for component in [x, y, 0xFFFFFFFF, 0xFFFF0000] {
            position.appendInteger(component)
        }
        return FinderRecord(filename: filename, property: "Iloc", type: "blob", value: position)
    }
}

private func backgroundAlias(root: URL, background: URL) throws -> Data {
    // icvp requires a Carbon AliasRecord, not Foundation bookmark data or an
    // alias file. Generate it on the mounted image so the volume identity and
    // file IDs survive compression; fromFilePath also supplies a relative base.
    // The deprecated API remains the system API for this legacy Finder format.
    // Swift no longer imports these deprecated declarations. Resolve the public
    // system functions with their C signatures from CarbonCore/Aliases.h;
    // MacTypes.h defines AliasHandle as a pointer to a pointer and Size as long.
    typealias AliasHandle = UnsafeMutablePointer<UnsafeMutableRawPointer?>
    typealias NewAlias = @convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>, UInt32,
        UnsafeMutablePointer<AliasHandle?>, UnsafeMutablePointer<UInt8>?
    ) -> Int32
    typealias AliasSize = @convention(c) (AliasHandle) -> Int
    typealias ReleaseAlias = @convention(c) (AliasHandle) -> Void
    let framework = "/System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/CarbonCore"
    guard let library = dlopen(framework, RTLD_NOW | RTLD_LOCAL) else {
        throw LayoutError(message: "Cannot load the system Alias Manager for the Finder background.")
    }
    defer { dlclose(library) }
    guard let createSymbol = dlsym(library, "FSNewAliasFromPath"),
          let sizeSymbol = dlsym(library, "GetAliasSize"),
          let releaseSymbol = dlsym(library, "DisposeHandle") else {
        throw LayoutError(message: "This macOS version does not provide the Finder Alias Manager functions.")
    }
    let createAlias = unsafeBitCast(createSymbol, to: NewAlias.self)
    let aliasSize = unsafeBitCast(sizeSymbol, to: AliasSize.self)
    let releaseAlias = unsafeBitCast(releaseSymbol, to: ReleaseAlias.self)
    var alias: AliasHandle?
    let status = root.path.withCString { rootPath in
        background.path.withCString { backgroundPath in
            createAlias(rootPath, backgroundPath, 0, &alias, nil)
        }
    }
    defer {
        if let alias { releaseAlias(alias) }
    }
    guard status == 0, let alias else {
        throw LayoutError(message: "Cannot create the Finder background alias (OSStatus \(status)).")
    }
    guard let bytes = alias.pointee else {
        throw LayoutError(message: "The system returned an empty Finder background alias.")
    }
    let size = aliasSize(alias)
    guard size > 0 else {
        throw LayoutError(message: "The system returned an invalid Finder background alias size.")
    }
    return Data(bytes: bytes, count: size)
}

private func finderStore(records: [FinderRecord]) throws -> Data {
    let ordered = records.sorted {
        let first = $0.filename.lowercased()
        let second = $1.filename.lowercased()
        return first == second ? $0.property < $1.property : first < second
    }
    var leaf = Data()
    leaf.appendInteger(UInt32(0)) // Leaf has no child pointer.
    leaf.appendInteger(UInt32(ordered.count))
    for record in ordered {
        leaf.append(record.encoded())
    }
    let pageSize = 4096
    guard leaf.count <= pageSize else {
        throw LayoutError(message: "Finder layout exceeds its single 4096-byte metadata page.")
    }

    // Buddy addresses omit the first four bytes of the file. The low five bits
    // of each address contain log2(block size). Reserve the header at 0x00,
    // B-tree metadata at 0x20, leaf at 0x1000, and allocator at 0x2000.
    let allocatorOffset = 0x2000
    var result = Data(count: allocatorOffset + pageSize + 4)
    var header = Data()
    header.appendInteger(UInt32(1))
    header.appendCode("Bud1")
    header.appendInteger(UInt32(allocatorOffset))
    header.appendInteger(UInt32(pageSize))
    header.appendInteger(UInt32(allocatorOffset))
    header.append(Data(count: 16))
    result.replaceSubrange(0..<header.count, with: header)

    var tree = Data()
    for field: UInt32 in [2, 0, UInt32(ordered.count), 1, UInt32(pageSize)] {
        tree.appendInteger(field)
    }
    result.replaceSubrange(0x24..<(0x24 + tree.count), with: tree)
    result.replaceSubrange(0x1004..<(0x1004 + leaf.count), with: leaf)

    var allocator = Data()
    allocator.appendInteger(UInt32(3))
    allocator.appendInteger(UInt32(0))
    let addresses: [UInt32] = [0x200C, 0x0025, 0x100C]
    for index in 0..<256 {
        allocator.appendInteger(index < addresses.count ? addresses[index] : UInt32(0))
    }
    allocator.appendInteger(UInt32(1)) // One table-of-contents entry.
    allocator.append(4)
    allocator.appendCode("DSDB")
    allocator.appendInteger(UInt32(1)) // B-tree metadata block ID.

    // Describe all unallocated buddies, including the initially unmaterialized
    // space up to 2 GiB, so Finder can also update this file on a writable image.
    for power in 0..<32 {
        let freeOffset: UInt32?
        switch power {
        case 6...11, 14...30: freeOffset = UInt32(1) << power
        case 12: freeOffset = 0x3000
        default: freeOffset = nil
        }
        allocator.appendInteger(UInt32(freeOffset == nil ? 0 : 1))
        if let freeOffset { allocator.appendInteger(freeOffset) }
    }
    guard allocator.count <= pageSize else {
        throw LayoutError(message: "Finder allocator metadata exceeds its reserved page.")
    }
    result.replaceSubrange((allocatorOffset + 4)..<(allocatorOffset + 4 + allocator.count), with: allocator)
    return result
}

private func configureLayout(at root: URL) throws {
    let background = root.appendingPathComponent(".background/installer.tiff")
    let fileManager = FileManager.default
    for name in ["Open Ratio.app", "Applications", ".background/installer.tiff"] {
        guard fileManager.fileExists(atPath: root.appendingPathComponent(name).path) else {
            throw LayoutError(message: "Missing installer item: \(name)")
        }
    }
    let alias = try backgroundAlias(root: root, background: background)
    let window: [String: Any] = [
        "WindowBounds": "{{240, 140}, {580, 440}}",
        "ShowToolbar": false, "ShowSidebar": false, "ShowStatusBar": false,
        "ShowPathbar": false, "ShowTabView": false, "ContainerShowSidebar": false,
        "PreviewPaneVisibility": false, "SidebarWidth": 0.0
    ]
    let icons: [String: Any] = [
        "viewOptionsVersion": 1, "backgroundType": 2, "backgroundImageAlias": alias,
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
        "arrangeBy": "none", "showIconPreview": false, "showItemInfo": false,
        "labelOnBottom": true, "textSize": 13.0, "iconSize": 128.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0
    ]
    var version = Data()
    version.appendInteger(UInt32(1))
    let records = [
        try FinderRecord.plist("bwsp", window),
        try FinderRecord.plist("icvp", icons),
        FinderRecord(filename: ".", property: "icvl", type: "type", value: Data("icnv".utf8)),
        FinderRecord(filename: ".", property: "vSrn", type: "long", value: version),
        FinderRecord.icon("Open Ratio.app", x: 130, y: 160),
        FinderRecord.icon("Applications", x: 450, y: 160)
    ]
    try finderStore(records: records).write(to: root.appendingPathComponent(".DS_Store"), options: .atomic)
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw LayoutError(message: "Usage: swift scripts/configure-dmg-layout.swift <mounted-image-directory>")
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
    try configureLayout(at: root)
    print("Configured Finder installer layout: \(root.path)")
} catch {
    FileHandle.standardError.write(Data("DMG layout error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
