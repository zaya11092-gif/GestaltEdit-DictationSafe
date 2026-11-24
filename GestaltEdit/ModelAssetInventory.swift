import Foundation

/// Read-only inventory of the on-device generative-model asset store.
///
/// Two properties of that store defeat a plain directory listing, and between
/// them they have kept the real answer out of reach on device:
///
/// 1. Downloaded bundles do not sit at the namespace root. The asset system
///    parks them inside `purpose_auto/`, so a root listing reports "no
///    .asset bundles" while the model is fully present one level down.
/// 2. An asset's directory name says nothing about which model it is. An
///    iOS 18–26 GreyMatter bundle and an iOS 27 one look identical by name.
///    Only the bundle's own `Info.plist` and its size on disk distinguish
///    them — and that distinction is what separates the explanations for a
///    completed download that never becomes a working feature:
///
///    - the catalog served an older-generation model, so the old stack runs
///      and the new one has nothing to load;
///    - the model is present and the runtime still refuses it, which puts
///      the wall in provisioning or attestation, past every plist layer;
///    - no weights were served at all and only a manifest landed.
///
/// Everything here is pure apart from `measureBundle`, which only stats.
enum ModelAssetInventory {

    /// A downloaded asset bundle, as described by its own plist.
    struct AssetBundle: Identifiable {
        let name: String
        /// Path of the bundle's Info.plist, relative to the leased directory.
        let infoPath: String
        /// Absolute path of the bundle directory.
        let directoryPath: String
        /// Flattened, display-ready `key = value` pairs.
        let properties: [(String, String)]
        let sizeInBytes: Int64?
        /// True when the size scan hit its entry cap, so the figure is a
        /// lower bound rather than the whole bundle.
        let sizeWasTruncated: Bool

        var id: String { directoryPath }
    }

    static let bundleDirectoryExtension = ".asset"

    /// Asset plists nest the descriptive keys one level down; both spellings
    /// are in use across asset types.
    static let nestedPropertyKeys = ["AssetProperties", "MobileAssetProperties"]

    /// Keys worth surfacing from the nested dictionaries. Matched
    /// case-insensitively as substrings so that a schema change on a later
    /// build still reports a value instead of silently reporting nothing.
    static let propertyKeyFragments = [
        "version", "build", "model", "device", "platform",
        "compat", "class", "requires", "generation", "purpose",
    ]

    /// The subset of those keys that actually identify which model a bundle
    /// is — what `summary` puts on one line.
    static let identifyingKeyFragments = ["version", "model", "build", "deviceclass"]

    /// Names of `.asset` directories in a directory listing, sorted.
    static func bundleNames(in listing: [String]) -> [String] {
        listing.filter { $0.hasSuffix(bundleDirectoryExtension) }.sorted()
    }

    /// Flattens an asset Info.plist into ordered `key = value` pairs: the
    /// top-level entries first, then the nested property dictionaries,
    /// filtered to descriptive keys. Binary blobs are reduced to their size
    /// and long strings shortened so a report stays readable.
    static func flattenedProperties(_ plist: [String: Any], limit: Int = 24) -> [(String, String)] {
        var pairs: [(String, String)] = []

        for key in plist.keys.sorted() where !nestedPropertyKeys.contains(key) {
            if let value = describe(plist[key]) { pairs.append((key, value)) }
        }

        for nestedKey in nestedPropertyKeys {
            guard let nested = plist[nestedKey] as? [String: Any] else { continue }
            for key in nested.keys.sorted() where isDescriptive(key) {
                if let value = describe(nested[key]) {
                    pairs.append(("\(nestedKey).\(key)", value))
                }
            }
        }

        return Array(pairs.prefix(limit))
    }

    static func isDescriptive(_ key: String) -> Bool {
        let lower = key.lowercased()
        return propertyKeyFragments.contains { lower.contains($0) }
    }

    /// A display string for a plist value, or nil for anything that would
    /// not be useful in a report.
    static func describe(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.count <= 120 ? string : String(string.prefix(117)) + "..."
        case let number as NSNumber:
            return number.stringValue
        case let data as Data:
            return "<\(data.count) bytes>"
        case let array as [Any]:
            let parts = array.prefix(4).compactMap { describe($0) }
            guard !parts.isEmpty else { return nil }
            let more = array.count > 4 ? " +\(array.count - 4)" : ""
            return "[" + parts.joined(separator: ", ") + "]" + more
        case let dictionary as [String: Any]:
            return "\(dictionary.count) keys"
        default:
            return nil
        }
    }

    /// Human-readable byte count.
    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// How a bundle's size reads against the expectation that the generative
    /// model is a multi-gigabyte download. This is the cheapest decisive
    /// datum: a stub cannot be a model.
    static func sizeVerdict(_ bytes: Int64) -> String {
        if bytes >= 500_000_000 { return "consistent with model weights" }
        if bytes >= 100_000_000 { return "too small for the full model" }
        return "manifest-sized, not model weights"
    }

    /// One line: size, what that size implies, and the properties that
    /// identify the model.
    static func summary(for bundle: AssetBundle) -> String {
        var parts: [String] = []

        if let size = bundle.sizeInBytes {
            parts.append(formattedSize(size) + (bundle.sizeWasTruncated ? "+" : ""))
            parts.append(sizeVerdict(size))
        } else {
            parts.append("size unavailable")
        }

        let identifying = bundle.properties.filter { pair in
            let lower = pair.0.lowercased()
            return identifyingKeyFragments.contains { lower.contains($0) }
        }
        if !identifying.isEmpty {
            parts.append(identifying.prefix(4).map { "\($0.0)=\($0.1)" }.joined(separator: " · "))
        }

        return parts.joined(separator: " · ")
    }

    /// Sums the regular files inside a bundle directory. `entryLimit` bounds
    /// the walk so a pathological directory cannot stall the Device Doctor;
    /// when it is reached, `truncated` is true and the total is a lower
    /// bound. Returns a nil size when the path is not a directory.
    static func measureBundle(at path: String, entryLimit: Int = 5_000) -> (size: Int64?, truncated: Bool) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else {
            return (nil, false)
        }

        var total: Int64 = 0
        var seen = 0
        for case let fileURL as URL in enumerator {
            seen += 1
            if seen > entryLimit { return (total, true) }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return (total, false)
    }
}
