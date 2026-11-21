import Foundation
import Darwin

struct AIRegionProfile: Equatable {
    let marketingName: String
    let regulatoryModel: String

    init(marketingName: String, regulatoryModel: String) {
        self.marketingName = marketingName
        self.regulatoryModel = regulatoryModel
    }

    // Keep the legacy iPhone marketing-name fallback in sync with the
    // authoritative product table. iPad names do not distinguish Wi-Fi/cellular.
    private static let regulatoryModels: [String: String] = productTypes.reduce(into: [:]) { models, entry in
        guard entry.key.hasPrefix("iPhone") else { return }
        models[entry.value.marketingName] = entry.value.regulatoryModel
    }

    // Model numbers: https://support.apple.com/en-us/108044
    // Identifiers: https://github.com/libimobiledevice/libirecovery/blob/master/src/libirecovery.c
    private static let productTypes: [String: AIRegionProfile] = [
        "iPhone16,1": .init(marketingName: "iPhone 15 Pro", regulatoryModel: "A2848"),
        "iPhone16,2": .init(marketingName: "iPhone 15 Pro Max", regulatoryModel: "A2849"),
        "iPhone17,1": .init(marketingName: "iPhone 16 Pro", regulatoryModel: "A3083"),
        "iPhone17,2": .init(marketingName: "iPhone 16 Pro Max", regulatoryModel: "A3084"),
        "iPhone17,3": .init(marketingName: "iPhone 16", regulatoryModel: "A3081"),
        "iPhone17,4": .init(marketingName: "iPhone 16 Plus", regulatoryModel: "A3082"),
        "iPhone17,5": .init(marketingName: "iPhone 16e", regulatoryModel: "A3212"),
        "iPhone18,1": .init(marketingName: "iPhone 17 Pro", regulatoryModel: "A3256"),
        "iPhone18,2": .init(marketingName: "iPhone 17 Pro Max", regulatoryModel: "A3257"),
        "iPhone18,3": .init(marketingName: "iPhone 17", regulatoryModel: "A3258"),
        "iPhone18,4": .init(marketingName: "iPhone Air", regulatoryModel: "A3260"),
        "iPhone18,5": .init(marketingName: "iPhone 17e", regulatoryModel: "A3575"),
        "iPhone19,2": .init(marketingName: "iPhone 18 Pro", regulatoryModel: "A3472"),
        "iPhone19,3": .init(marketingName: "iPhone 18 Pro Max", regulatoryModel: "A3473"),
        // The global variant uses a different board; region conversion retains
        // its product identity and follows the existing US regulatory mapping.
        "iPhone19,7": .init(marketingName: "iPhone 18 Pro Max", regulatoryModel: "A3473"),
        "iPhone19,4": .init(marketingName: "iPhone Duo", regulatoryModel: "A3447"),

        // Apple Intelligence iPads. Cellular variants map to their US
        // equivalent, including devices sold originally in mainland China.
        "iPad13,4": .init(marketingName: "iPad Pro 11-inch (M1)", regulatoryModel: "A2377"),
        "iPad13,5": .init(marketingName: "iPad Pro 11-inch (M1)", regulatoryModel: "A2459"),
        "iPad13,6": .init(marketingName: "iPad Pro 11-inch (M1)", regulatoryModel: "A2301"),
        "iPad13,7": .init(marketingName: "iPad Pro 11-inch (M1)", regulatoryModel: "A2301"),
        "iPad13,8": .init(marketingName: "iPad Pro 12.9-inch (M1)", regulatoryModel: "A2378"),
        "iPad13,9": .init(marketingName: "iPad Pro 12.9-inch (M1)", regulatoryModel: "A2461"),
        "iPad13,10": .init(marketingName: "iPad Pro 12.9-inch (M1)", regulatoryModel: "A2379"),
        "iPad13,11": .init(marketingName: "iPad Pro 12.9-inch (M1)", regulatoryModel: "A2379"),
        "iPad13,16": .init(marketingName: "iPad Air (M1)", regulatoryModel: "A2588"),
        "iPad13,17": .init(marketingName: "iPad Air (M1)", regulatoryModel: "A2589"),
        "iPad14,3": .init(marketingName: "iPad Pro 11-inch (M2)", regulatoryModel: "A2759"),
        "iPad14,4": .init(marketingName: "iPad Pro 11-inch (M2)", regulatoryModel: "A2435"),
        "iPad14,5": .init(marketingName: "iPad Pro 12.9-inch (M2)", regulatoryModel: "A2436"),
        "iPad14,6": .init(marketingName: "iPad Pro 12.9-inch (M2)", regulatoryModel: "A2764"),
        "iPad14,8": .init(marketingName: "iPad Air 11-inch (M2)", regulatoryModel: "A2902"),
        "iPad14,9": .init(marketingName: "iPad Air 11-inch (M2)", regulatoryModel: "A2903"),
        "iPad14,10": .init(marketingName: "iPad Air 13-inch (M2)", regulatoryModel: "A2898"),
        "iPad14,11": .init(marketingName: "iPad Air 13-inch (M2)", regulatoryModel: "A2899"),
        "iPad15,3": .init(marketingName: "iPad Air 11-inch (M3)", regulatoryModel: "A3266"),
        "iPad15,4": .init(marketingName: "iPad Air 11-inch (M3)", regulatoryModel: "A3267"),
        "iPad15,5": .init(marketingName: "iPad Air 13-inch (M3)", regulatoryModel: "A3268"),
        "iPad15,6": .init(marketingName: "iPad Air 13-inch (M3)", regulatoryModel: "A3269"),
        "iPad16,1": .init(marketingName: "iPad mini (A17 Pro)", regulatoryModel: "A2993"),
        "iPad16,2": .init(marketingName: "iPad mini (A17 Pro)", regulatoryModel: "A2995"),
        "iPad16,3": .init(marketingName: "iPad Pro 11-inch (M4)", regulatoryModel: "A2836"),
        "iPad16,4": .init(marketingName: "iPad Pro 11-inch (M4)", regulatoryModel: "A2837"),
        "iPad16,5": .init(marketingName: "iPad Pro 13-inch (M4)", regulatoryModel: "A2925"),
        "iPad16,6": .init(marketingName: "iPad Pro 13-inch (M4)", regulatoryModel: "A2926"),
        "iPad16,8": .init(marketingName: "iPad Air 11-inch (M4)", regulatoryModel: "A3459"),
        "iPad16,9": .init(marketingName: "iPad Air 11-inch (M4)", regulatoryModel: "A3460"),
        "iPad16,10": .init(marketingName: "iPad Air 13-inch (M4)", regulatoryModel: "A3461"),
        "iPad16,11": .init(marketingName: "iPad Air 13-inch (M4)", regulatoryModel: "A3462"),
        "iPad17,1": .init(marketingName: "iPad Pro 11-inch (M5)", regulatoryModel: "A3357"),
        "iPad17,2": .init(marketingName: "iPad Pro 11-inch (M5)", regulatoryModel: "A3358"),
        "iPad17,3": .init(marketingName: "iPad Pro 13-inch (M5)", regulatoryModel: "A3360"),
        "iPad17,4": .init(marketingName: "iPad Pro 13-inch (M5)", regulatoryModel: "A3361")
    ]

    init?(plist: GestaltPlist) {
        let cacheExtra = plist.cacheExtra
        let marketingKeys = [
            "Z/dqyWS6OZTRy10UcmUAhw",
            "bbtR9jQx50Fv5Af/affNtA"
        ]

        let storedName = marketingKeys
            .compactMap { cacheExtra[$0] as? String }
            .first { Self.regulatoryModels[$0] != nil }
        let productType = Self.detectedProductType(in: plist)
        if let profile = Self.profile(forProductType: productType) {
            self = profile
            return
        }

        guard let marketingName = storedName,
              let regulatoryModel = Self.regulatoryModels[marketingName] else {
            return nil
        }
        self.marketingName = marketingName
        self.regulatoryModel = regulatoryModel
    }

    static func profile(forProductType productType: String) -> AIRegionProfile? {
        if let profile = productTypes[productType] {
            return profile
        }

        // MobileGestalt can append a board/configuration suffix (for example,
        // "iPad16,3-A"). The device family identifier before the suffix is the
        // stable value used by the model map.
        guard let separator = productType.firstIndex(of: "-") else { return nil }
        return productTypes[String(productType[..<separator])]
    }

    fileprivate static func detectedProductType(in plist: GestaltPlist) -> String {
        plist.cacheExtra["0+nc/Udy4WNG8S+Q7a/s1A"] as? String ?? machineIdentifier
    }

    static var currentDeviceMarketingName: String? {
        profile(forProductType: machineIdentifier)?.marketingName
    }

    // Test hook: overrides the kernel answer so the resolution logic can be
    // exercised for any device class on the build machine. Nil in production.
    static var machineIdentifierOverride: String?

    // The physical product type reported by the kernel. Repair flows compare
    // stored identities against this value; it is independent of the cache.
    static var machineIdentifier: String {
        if let machineIdentifierOverride { return machineIdentifierOverride }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0,
              size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &value, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: value)
    }
}

// Siri AI two-stage unlock, ported from H4CNPE/YumEdit's older-device flow
// (GPL-3.0). The eligibility gate lives in three CacheData booleans (see
// CacheDataUnlock); the capability surface is driven by the US sales region
// (LL/LL/A), SiriMode 2 and the generative-model capability flag in
// CacheExtra. Stage 1 writes those and optionally borrows an eligible
// ProductType — ProductType ONLY: board, CPU, thinning type and the
// regulatory model stay physical, which is what keeps Face ID and dictation
// recoverable and makes the revert trivial. After a full restart and a
// completed resource download, stage 2 restores the real identity from a
// trusted same-CacheUUID backup while every capability write and the
// patched CacheData stay. After stage 2 the Siri settings page must never
// be opened: it re-runs eligibility against the restored hardware and can
// invalidate the downloaded resources — YumEdit's documented failure mode.
// The fork's earlier full-identity borrow and the invented iOS 27
// persistence keys are gone: iOS scrubbed those CacheExtra flags whenever
// the CacheData gate was closed, which is why the previous approach wrote
// keys that never activated and later vanished.
enum SiriAIYumUnlock {
    static let siriModeKey = "a3n5T9sFtlyQ74NEp9ESxg"
    static let generativeCapabilityKey = "A62OafQ85EJAiiqKn4agtg"
    static let countryKey = "h63QSdBCiT/z0WU6rdQv6Q"
    static let regionKey = "yK+xavymRGZ3xWc1tb8XDg"
    static let cacheDataKey = "CacheData"
    static let cacheUUIDKey = "CacheUUID"

    struct BorrowProfile: Identifiable, Hashable {
        let product: String
        let name: String
        var id: String { product }
    }

    // Eligible ProductTypes for the optional borrow, from YumEdit's profile
    // list. Only the ProductType is written; the physical board, CPU and
    // regulatory model are never borrowed.
    static let borrowProfiles: [BorrowProfile] = [
        .init(product: "iPhone16,1", name: "iPhone 15 Pro"),
        .init(product: "iPhone16,2", name: "iPhone 15 Pro Max"),
        .init(product: "iPhone17,3", name: "iPhone 16"),
        .init(product: "iPhone17,4", name: "iPhone 16 Plus"),
        .init(product: "iPhone17,1", name: "iPhone 16 Pro"),
        .init(product: "iPhone17,2", name: "iPhone 16 Pro Max"),
        .init(product: "iPhone17,5", name: "iPhone 16e"),
        .init(product: "iPhone18,3", name: "iPhone 17"),
        .init(product: "iPhone18,1", name: "iPhone 17 Pro"),
        .init(product: "iPhone18,2", name: "iPhone 17 Pro Max"),
        .init(product: "iPhone18,4", name: "iPhone Air"),
        .init(product: "iPhone18,5", name: "iPhone 17e")
    ]

    struct State: Equatable {
        var identityMatchesHardware: Bool
        var borrowedProduct: String?
        var isUSRegion: Bool
        var siriMode: Int?
        var generativeCapability: Bool
        var cacheDataPresent: Bool
        var cacheDataBitsReady: Bool

        var isBorrowed: Bool { borrowedProduct != nil }
        var capabilitiesWritten: Bool {
            isUSRegion && siriMode == 2 && generativeCapability && cacheDataBitsReady
        }
        /// Stage-1 end state: capabilities written under an active borrow.
        var stageOneBorrowActive: Bool { capabilitiesWritten && isBorrowed }
        /// Stage-2 end state: real identity restored, capabilities kept.
        var unlockActive: Bool { capabilitiesWritten && !isBorrowed && identityMatchesHardware }
    }

    static func state(of plist: GestaltPlist, machine: String = AIRegionProfile.machineIdentifier) -> State {
        let extra = plist.cacheExtra
        let cached = extra[DictationRepairRestore.productType] as? String
        let cacheData = plist.dict[cacheDataKey] as? Data
        return State(
            identityMatchesHardware: cached == machine
                && extra[DictationRepairRestore.hardwareModel] as? String == DeviceIdentityAudit.expectedBoard(for: machine)
                && extra[DictationRepairRestore.cpuModel] as? String == DeviceIdentityAudit.expectedCPU(for: machine),
            borrowedProduct: cached.flatMap { product in
                product != machine && borrowProfiles.contains { $0.product == product } ? product : nil
            },
            isUSRegion: (extra[countryKey] as? String) == "LL" && (extra[regionKey] as? String) == "LL/A",
            siriMode: extra[siriModeKey] as? Int,
            generativeCapability: (extra[generativeCapabilityKey] as? Int) == 1,
            cacheDataPresent: cacheData != nil,
            cacheDataBitsReady: cacheData.map { CacheDataUnlock.bitsReady($0) } ?? false
        )
    }

    /// Stage 1: verify the cache carries the physical identity and a
    /// consistent sales region, then write LL/LL/A, SiriMode 2, the
    /// generative capability flag, the optional ProductType borrow and the
    /// patched CacheData — all in one verified save.
    static func stageOne(plist: GestaltPlist,
                         machine: String,
                         expectedBoard: String?,
                         expectedCPU: String?,
                         borrowProduct: String?) throws -> GestaltPlist {
        guard !machine.isEmpty, expectedBoard != nil, expectedCPU != nil else {
            throw SiriAIUnlockError.machineUnknown
        }
        if let borrowProduct, !borrowProfiles.contains(where: { $0.product == borrowProduct }) {
            throw SiriAIUnlockError.unknownBorrowProfile
        }
        let extra = plist.cacheExtra
        guard (extra[DictationRepairRestore.productType] as? String ?? machine) == machine else {
            throw SiriAIUnlockError.identitySpoofed
        }
        guard extra[DictationRepairRestore.hardwareModel] as? String == expectedBoard,
              extra[DictationRepairRestore.cpuModel] as? String == expectedCPU else {
            throw SiriAIUnlockError.identityMismatch
        }
        let country = extra[countryKey] as? String
        let region = extra[regionKey] as? String
        guard let country, !country.isEmpty, region == "\(country)/A" else {
            throw SiriAIUnlockError.regionInconsistent
        }
        if borrowProduct == nil, country == "LL", region == "LL/A",
           (extra[siriModeKey] as? Int) == 2,
           (extra[generativeCapabilityKey] as? Int) == 1,
           (plist.dict[cacheDataKey] as? Data).map({ CacheDataUnlock.bitsReady($0) }) == true {
            throw SiriAIUnlockError.alreadyComplete
        }
        guard var cacheData = plist.dict[cacheDataKey] as? Data else {
            throw SiriAIUnlockError.cacheDataMissing
        }
        cacheData = try CacheDataUnlock.patch(cacheData)

        var result = plist
        var written = extra
        written[countryKey] = "LL"
        written[regionKey] = "LL/A"
        if let borrowProduct { written[DictationRepairRestore.productType] = borrowProduct }
        written[siriModeKey] = 2
        written[generativeCapabilityKey] = 1
        result.cacheExtra = written
        result.setValue(cacheData, forKey: cacheDataKey)
        return result
    }

    /// Stage 2: restore every identity key from the verified physical backup
    /// (covering both this fork's old full borrow and the ProductType-only
    /// borrow) while region, SiriMode, the capability flag and CacheData stay
    /// exactly as cached.
    static func stageTwo(current: GestaltPlist, identitySource: GestaltPlist) throws -> GestaltPlist {
        let currentProduct = current.cacheExtra[DictationRepairRestore.productType] as? String
        let sourceProduct = identitySource.cacheExtra[DictationRepairRestore.productType] as? String
        guard let currentProduct, let sourceProduct, currentProduct != sourceProduct else {
            throw SiriAIUnlockError.notBorrowed
        }
        guard (current.cacheExtra[countryKey] as? String) == "LL",
              (current.cacheExtra[regionKey] as? String) == "LL/A" else {
            throw SiriAIUnlockError.regionInconsistent
        }
        return DictationRepairRestore.restoring(current, from: identitySource)
    }

    /// YumEdit's trusted-backup provenance rules: same CacheUUID, CacheData
    /// provenance (identical, or the backup's blob patched forward equals the
    /// current one), and a CacheExtra whose ProductType, board and CPU are
    /// the physical device. `backups` are newest-first.
    static func trustedIdentitySource(current: GestaltPlist,
                                      machine: String,
                                      expectedBoard: String?,
                                      expectedCPU: String?,
                                      backups: [GestaltPlist]) -> GestaltPlist? {
        guard let currentUUID = current.dict[cacheUUIDKey] as? String,
              let currentData = current.dict[cacheDataKey] as? Data,
              !machine.isEmpty, expectedBoard != nil, expectedCPU != nil else { return nil }
        for backup in backups {
            guard backup.dict[cacheUUIDKey] as? String == currentUUID,
                  let originalData = backup.dict[cacheDataKey] as? Data,
                  originalData == currentData || (try? CacheDataUnlock.patch(originalData)) == currentData,
                  backup.cacheExtra[DictationRepairRestore.productType] as? String == machine,
                  backup.cacheExtra[DictationRepairRestore.hardwareModel] as? String == expectedBoard,
                  backup.cacheExtra[DictationRepairRestore.cpuModel] as? String == expectedCPU else { continue }
            return backup
        }
        return nil
    }

    /// The pre-unlock CacheData for a full AI revert: a same-CacheUUID backup
    /// whose blob, patched forward, equals the current one. Restoring it
    /// closes the eligibility gate again.
    static func originalCacheData(current: GestaltPlist, backups: [GestaltPlist]) -> Data? {
        guard let currentUUID = current.dict[cacheUUIDKey] as? String,
              let currentData = current.dict[cacheDataKey] as? Data,
              CacheDataUnlock.bitsReady(currentData) else { return nil }
        for backup in backups {
            guard backup.dict[cacheUUIDKey] as? String == currentUUID,
                  let originalData = backup.dict[cacheDataKey] as? Data,
                  originalData != currentData,
                  (try? CacheDataUnlock.patch(originalData)) == currentData else { continue }
            return originalData
        }
        return nil
    }
}

struct GestaltNotice: Identifiable {
    enum Kind { case error, backupCreated, riskWarning, saved, repaired }

    let id = UUID()
    let kind: Kind
    let message: String

    var title: String {
        switch kind {
        case .error: String(localized: "Operation Failed")
        case .backupCreated: String(localized: "Backup Complete")
        case .saved: String(localized: "Saved to Apple Watch")
        case .riskWarning: String(localized: "High Risk")
        case .repaired: String(localized: "Repair Complete")
        }
    }
}

enum PlistValueKind: String, CaseIterable, Identifiable {
    case string
    case integer
    case float
    case boolean
    case data
    case array
    case dictionary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .string: String(localized: "String")
        case .integer: String(localized: "Integer")
        case .float: String(localized: "Float")
        case .boolean: String(localized: "Boolean")
        case .data: String(localized: "Data")
        case .array: String(localized: "Array")
        case .dictionary: String(localized: "Dictionary")
        }
    }

    static func kind(of value: Any?) -> PlistValueKind {
        switch value {
        case is String:
            .string
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .boolean
                : (CFNumberIsFloatType(number) ? .float : .integer)
        case is Data:
            .data
        case is NSArray:
            .array
        case is NSDictionary:
            .dictionary
        default:
            .string
        }
    }
}

struct PlistValueInfo {
    let kind: PlistValueKind
    let summary: String
    let searchText: String

    static func info(for value: Any?) -> PlistValueInfo {
        let kind = PlistValueKind.kind(of: value)
        let text = encode(value, as: kind)
        let summary: String

        switch kind {
        case .string:
            summary = text.isEmpty ? String(localized: "Empty string") : text
        case .integer, .float, .boolean:
            summary = text
        case .data:
            summary = String(format: String(localized: "Data (%d bytes)"), (value as? Data)?.count ?? 0)
        case .array:
            summary = String(format: String(localized: "Array (%d items)"), (value as? NSArray)?.count ?? 0)
        case .dictionary:
            summary = String(format: String(localized: "Dictionary (%d items)"), (value as? NSDictionary)?.count ?? 0)
        }

        return PlistValueInfo(kind: kind, summary: summary, searchText: text)
    }

    static func encode(_ value: Any?, as kind: PlistValueKind) -> String {
        switch kind {
        case .string:
            value as? String ?? ""
        case .integer, .float:
            (value as? NSNumber)?.stringValue ?? ""
        case .boolean:
            (value as? NSNumber)?.boolValue == true ? "true" : "false"
        case .data:
            (value as? Data)?.base64EncodedString() ?? ""
        case .array, .dictionary:
            jsonText(for: value)
        }
    }

    static func parse(_ text: String, as kind: PlistValueKind) throws -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .string:
            return text
        case .integer:
            guard let value = Int64(trimmed) else {
                throw PlistValueError.invalid(String(localized: "Invalid integer"))
            }
            return NSNumber(value: value)
        case .float:
            guard let value = Double(trimmed) else {
                throw PlistValueError.invalid(String(localized: "Invalid floating-point number"))
            }
            return NSNumber(value: value)
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "1", "yes":
                return NSNumber(value: true)
            case "false", "0", "no":
                return NSNumber(value: false)
            default:
                throw PlistValueError.invalid(String(localized: "Enter true or false"))
            }
        case .data:
            guard let data = Data(base64Encoded: trimmed) else {
                throw PlistValueError.invalid(String(localized: "Invalid Base64 data"))
            }
            return data
        case .array:
            return try jsonObject(from: trimmed, expected: NSArray.self)
        case .dictionary:
            return try jsonObject(from: trimmed, expected: NSDictionary.self)
        }
    }

    private static func jsonText(for value: Any?) -> String {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys]
              ) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func jsonObject<T>(from text: String, expected: T.Type) throws -> Any {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is T else {
            throw PlistValueError.invalid(
                String(format: String(localized: "Invalid JSON for type %@"), String(describing: T.self))
            )
        }
        return object
    }
}

enum PlistValueError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

struct GestaltPlist {
    var dict: [String: Any]

    var topLevelKeys: [String] {
        dict.keys.sorted()
    }

    var cacheExtra: [String: Any] {
        get { dict["CacheExtra"] as? [String: Any] ?? [:] }
        set { dict["CacheExtra"] = newValue }
    }

    var cacheExtraKeys: [String] {
        cacheExtra.keys.sorted()
    }

    func value(forKey key: String) -> Any? {
        dict[key]
    }

    mutating func setValue(_ value: Any, forKey key: String) {
        dict[key] = value
    }

    mutating func setCacheExtra(_ value: Any, forKey key: String) {
        var values = cacheExtra
        values[key] = value
        cacheExtra = values
    }

    mutating func removeCacheExtraValue(forKey key: String) {
        var values = cacheExtra
        values.removeValue(forKey: key)
        cacheExtra = values
    }

    /// Removes every cached answer so iOS rebuilds a fully native cache on
    /// the next restart. Used by the Device Doctor factory reset: unknown or
    /// foreign edits cannot survive a rebuild, because nothing is left to
    /// survive. The caller must create a backup first (the verified save
    /// path does this automatically).
    mutating func clearCacheExtra() {
        cacheExtra = [:]
    }
}

// Restore only fields changed by the identity spoof, preserving AI settings,
// downloaded-model eligibility and any unrelated edits made after setup.
enum SiriAIIdentityRestore {
    // Every key the AI Expansion borrow writes. The revert restores each one
    // from the pre-setup baseline, or removes it when the baseline had no
    // value, so no borrowed fragment survives.
    static let keys = [
        DictationRepairRestore.productType,
        DictationRepairRestore.hardwareModel,
        DictationRepairRestore.cpuModel,
        DictationRepairRestore.thinningProductType,
        DictationRepairRestore.hardwareModelStr,
        DictationRepairRestore.marketingName
    ]

    /// Restores the borrowed identity keys and keeps every AI key —
    /// capability flag, SiriMode, the iOS 27 expansion flag and the
    /// persistence triple. This is the finishing move of the unlock: the
    /// models were downloaded under the borrowed identity and are validated
    /// against the real hardware after the revert, so the AI keys must stay
    /// or Image Playground and the dedicated Siri app disappear again.
    /// Removing the AI keys deliberately is the Device Doctor's job.
    static func restoring(_ current: GestaltPlist, from original: GestaltPlist) -> GestaltPlist {
        var restored = current
        for key in keys {
            if let value = original.cacheExtra[key] {
                restored.setCacheExtra(value, forKey: key)
            } else {
                restored.removeCacheExtraValue(forKey: key)
            }
        }
        return restored
    }

    static func values(in plist: GestaltPlist) -> NSDictionary {
        values(keys, in: plist)
    }

    static func values(_ keys: [String], in plist: GestaltPlist) -> NSDictionary {
        NSDictionary(dictionary: plist.cacheExtra.filter { keys.contains($0.key) })
    }

    /// True when both plists describe the same physical identity across
    /// every key the borrow can touch. Used to prove a revert actually
    /// returned the device to its baseline identity.
    static func sameDevice(_ lhs: GestaltPlist, _ rhs: GestaltPlist) -> Bool {
        values(in: lhs).isEqual(values(in: rhs))
    }
}

// Repair path for dictation and Face ID damage left behind by a device
// spoof (from GestaltEdit, GestaltX, Gester, Nugget-based tools or any other
// editor). Restores the complete hardware identity — including the regulatory
// model number and the thinning/hardware-name variants different editors
// touch — plus the device-specific on-device Siri capability type, while AI
// flags, SiriMode, region settings and unrelated edits stay untouched. The
// repair source must describe the physical device; spoofed, foreign or
// incomplete identities are rejected rather than guessed.
enum DictationRepairRestore {
    static let productType = "h9jDsbgj7xIVeIQ8S3/X3Q"
    static let hardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
    static let cpuModel = "5pYKlGnYYBzGvAlIU8RjEQ"
    static let modelNumber = "97JDvERpVwO+GHtthIh7hA"
    // Device-specific Siri capability type. Editors that overwrite it break
    // the on-device speech pipeline used by dictation and spoken Siri.
    static let siriOnDevice = "K/R1GfGfCkXvEhaPS2Vrng"
    // Additional identity keys other editors spoof (ThinningProductType,
    // HWModelStr, GSDeviceName, marketing-name, PhysicalHardwareNameString).
    static let thinningProductType = "0+nc/Udy4WNG8S+Q7a/s1A"
    static let hardwareModelStr = "/YYygAofPDbhrwToVsXdeA"
    static let gsDeviceName = "9s45ldrCC1WF+7b6C4H2BA"
    static let marketingName = "Z/dqyWS6OZTRy10UcmUAhw"
    static let physicalHardwareName = "bbtR9jQx50Fv5Af/affNtA"

    static let keys = [productType, hardwareModel, cpuModel, modelNumber, siriOnDevice,
                       thinningProductType, hardwareModelStr, gsDeviceName,
                       marketingName, physicalHardwareName]

    static func matchesPhysicalDevice(_ plist: GestaltPlist,
                                      machine: String = AIRegionProfile.machineIdentifier) -> Bool {
        guard !machine.isEmpty else { return false }
        // Every product-type key stored in the backup must describe the
        // physical machine (editors spoof different subsets of these keys).
        var checked = 0
        for key in [productType, thinningProductType] {
            guard let stored = plist.cacheExtra[key] as? String, !stored.isEmpty else { continue }
            guard normalized(stored) == normalized(machine) else { return false }
            checked += 1
        }
        return checked > 0
    }

    static func restoring(_ current: GestaltPlist, from original: GestaltPlist) -> GestaltPlist {
        var restored = current
        for key in keys {
            if let value = original.cacheExtra[key] {
                restored.setCacheExtra(value, forKey: key)
            } else {
                restored.removeCacheExtraValue(forKey: key)
            }
        }
        return restored
    }

    static func values(in plist: GestaltPlist) -> NSDictionary {
        SiriAIIdentityRestore.values(keys, in: plist)
    }

    // MobileGestalt can append a board/configuration suffix (for example,
    // "iPad16,3-A"); the identifier before the suffix is the stable value.
    private static func normalized(_ product: String) -> String {
        String(product.split(separator: "-", maxSplits: 1).first ?? "")
    }
}
