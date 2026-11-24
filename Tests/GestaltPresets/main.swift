import Foundation

// xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/CacheDataUnlock.swift GestaltEdit/GestaltTweaks.swift GestaltEdit/GestaltBackupStore.swift GestaltEdit/DeviceIdentityAudit.swift Tests/GestaltPresets/main.swift -o /tmp/gestalt-preset-tests
let catalog = GestaltTweakCatalog.self
let iPad = catalog.definition(for: .iPadOS)!
let stage = catalog.definition(for: .stageManager)!
let apps = catalog.definition(for: .iPadApps)!
for component in [stage, apps] {
    for (key, value) in component.values {
        precondition(NSDictionary(dictionary: [key: value]).isEqual(to: [key: iPad.values[key]!]))
    }
}

var selection: Set<GestaltTweakID> = [.stageManager, .iPadApps, .bootChime]
selection = catalog.selecting(.iPadOS, enabled: true, in: selection)
precondition(selection == [.iPadOS, .bootChime])
selection = catalog.selecting(.stageManager, enabled: true, in: selection)
precondition(selection == [.iPadOS, .bootChime])
selection = catalog.selecting(.iPadOS, enabled: false, in: selection)
precondition(selection == [.bootChime])
selection = catalog.selecting(.stageManager, enabled: true, in: selection)
precondition(selection == [.bootChime, .stageManager])
selection = catalog.selecting(.enableLiquidGlassLowPerformance, enabled: true, in: selection)
selection = catalog.selecting(.disableLiquidGlassLowPerformance, enabled: true, in: selection)
precondition(!selection.contains(.enableLiquidGlassLowPerformance))
precondition(selection.contains(.disableLiquidGlassLowPerformance))

// A rejected binary patch must leave both CacheExtra and CacheData intact.
var invalid = GestaltPlist(dict: ["CacheExtra": ["existing": "keep"], "CacheData": Data([0, 1])])
let before = NSDictionary(dictionary: invalid.dict)
do {
    try invalid.apply(definition: iPad)
    fatalError("Expected invalid CacheData to fail")
} catch {
    precondition(before.isEqual(to: invalid.dict))
}

// Exercise the existing validated marker path with a synthetic cache, keeping
// all unrelated bytes and capability values intact.
var hex = Array(repeating: Character("0"), count: 2000)
for (index, value) in Array("abcd").enumerated() { hex[1700 + index] = value }
hex[1700 - 67] = "1"
hex[1700 + 13] = "1"
func bytes(_ hex: [Character]) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map { UInt8(String(hex[$0...($0 + 1)]), radix: 16)! })
}
let originalData = bytes(hex)
var valid = GestaltPlist(dict: ["CacheExtra": ["existing": "keep"], "CacheData": originalData])
try valid.apply(definition: iPad)
hex[1700 - 67] = "3"
precondition(valid.dict["CacheData"] as? Data == bytes(hex))
precondition(valid.cacheExtra["existing"] as? String == "keep")
precondition(valid.cacheExtra["qeaj75wk3HF4DwQ8qbIi7g"] as? Int == 1)
precondition(valid.cacheExtra["9MZ5AdH43csAUajl/dU+IQ"] as? [Int] == [1, 2])
let applied = NSDictionary(dictionary: valid.dict)
try valid.apply(definition: iPad)
precondition(applied.isEqual(to: valid.dict))

var island = GestaltPlist(dict: ["CacheExtra": ["oPeik/9e8lQWMszEjbPzng": ["keep": 42]]])
try island.setDynamicIslandSubtype(2556)
precondition(island.cacheExtra["YlEtTtHlNesRBMal1CqRaA"] as? Int == 1)
precondition((island.cacheExtra["oPeik/9e8lQWMszEjbPzng"] as? [String: Any])?["keep"] as? Int == 42)
print("Passed: iPad bundle, selection dependencies, Glass exclusivity, atomic failure, validated CacheData patch, reapplication and Dynamic Island.")

let os26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
let os264 = OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
let os27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
let highAOD = catalog.definition(for: .aodHighLuminance)!
precondition(!highAOD.isAvailable(on: os26) && highAOD.isAvailable(on: os27))
var unsupported = GestaltPlist(dict: ["CacheExtra": ["keep": "original"], "CacheData": Data([1, 2, 3])])
let unsupportedOriginal = NSDictionary(dictionary: unsupported.dict)
do {
    try unsupported.apply(definition: highAOD, on: os26)
    fatalError("Expected unsupported system version to fail")
} catch {
    precondition(unsupportedOriginal.isEqual(to: unsupported.dict))
}

// Capability-only presets must not change device identity or binary CacheData.
var capabilities = GestaltPlist(dict: ["CacheExtra": ["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4"], "CacheData": Data([1, 2, 3])])
for definition in catalog.definitions where definition.showsDetails {
    try capabilities.apply(definition: definition, on: os27)
}
precondition(capabilities.dict["CacheData"] as? Data == Data([1, 2, 3]))
precondition(capabilities.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String == "iPhone15,4")
precondition(capabilities.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] == nil)
let serialized = try PropertyListSerialization.data(fromPropertyList: capabilities.dict, format: .binary, options: 0)
let roundTrip = try PropertyListSerialization.propertyList(from: serialized, format: nil) as! [String: Any]
precondition(NSDictionary(dictionary: capabilities.dict).isEqual(to: roundTrip))

for region in GestaltRegionPreset.all {
    var regional = GestaltPlist(dict: ["CacheExtra": ["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4", "a3n5T9sFtlyQ74NEp9ESxg": 2]])
    regional.apply(region: region)
    precondition(regional.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == region.code)
    precondition(regional.cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] as? String == region.salesCode)
    precondition(regional.cacheExtra.count == 4)
}
precondition(Set(catalog.definitions.map(\.id)) == Set(GestaltTweakID.allCases))
precondition(catalog.definitions.count == Set(catalog.definitions.map(\.id)).count)
print("Passed: OS 26/27 boundaries, rejected-write atomicity, capability-only identity preservation, binary plist round-trip and independent region presets.")

// MARK: - CacheDataUnlock: the three eligibility booleans inside CacheData

do {
    var blob = Data(count: 0xFC8 + 8)
    precondition(!CacheDataUnlock.bitsReady(blob), "closed gate must not read as ready")
    let patched = try CacheDataUnlock.patch(blob)
    precondition(patched[0x720] == 1 && patched[0xBF0] == 0 && patched[0xFC8] == 1)
    for target in CacheDataUnlock.bitTargets {
        precondition(patched[(target.offset + 1)..<(target.offset + 8)].allSatisfy { $0 == 0 })
    }
    precondition(CacheDataUnlock.bitsReady(patched), "patched blob must read as ready")

    // A cell that already holds the target value patches idempotently.
    var open = patched
    open[0x720] = 0
    let rePatched = try CacheDataUnlock.patch(open)
    precondition(rePatched == patched, "patch is idempotent for 0/1 cells")

    // Unknown layouts are refused instead of guessed.
    var garbage = Data(count: 0xFC8 + 8)
    garbage[0x720] = 2
    do {
        _ = try CacheDataUnlock.patch(garbage)
        fatalError("Expected unknown CacheData layout to fail")
    } catch { }
    var contaminated = try CacheDataUnlock.patch(Data(count: 0xFC8 + 8))
    contaminated[0xFC9] = 7
    do {
        _ = try CacheDataUnlock.patch(contaminated)
        fatalError("Expected non-zero neighbours to fail")
    } catch { }
    do {
        _ = try CacheDataUnlock.patch(Data([1, 2, 3]))
        fatalError("Expected short CacheData to fail")
    } catch { }
    precondition(!CacheDataUnlock.bitsReady(Data([1, 2, 3])))
}
print("Passed: CacheData eligibility bits patch idempotently and refuse unknown layouts.")

// MARK: - Stage 1: US region + SiriMode + capability + CacheData gate

let unlockMachine = "iPhone15,4"
let unlockBoard = "D37AP"
let unlockCPU = "t8120"
func unlockCache(product: String? = nil, board: String? = nil, cpu: String? = nil,
                 country: String? = "CH", region: String? = nil, extra: [String: Any] = [:],
                 cacheData: Data? = nil, cacheUUID: String = "UUID-1") -> GestaltPlist {
    var cache: [String: Any] = [
        DictationRepairRestore.hardwareModel: board ?? unlockBoard,
        DictationRepairRestore.cpuModel: cpu ?? unlockCPU,
    ]
    cache[DictationRepairRestore.productType] = product ?? unlockMachine
    cache[SiriAIYumUnlock.countryKey] = country ?? ""
    cache[SiriAIYumUnlock.regionKey] = region ?? "\(country ?? "")/A"
    cache["97JDvERpVwO+GHtthIh7hA"] = "A2846"
    for (key, value) in extra { cache[key] = value }
    var dict: [String: Any] = ["CacheExtra": cache, SiriAIYumUnlock.cacheUUIDKey: cacheUUID]
    dict[SiriAIYumUnlock.cacheDataKey] = cacheData ?? Data(count: 0xFC8 + 8)
    return GestaltPlist(dict: dict)
}

do {
    // Capability-only stage 1: identity untouched, capabilities + gate written.
    let plain = unlockCache()
    let staged = try SiriAIYumUnlock.stageOne(
        plist: plain, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil)
    let state = SiriAIYumUnlock.state(of: staged, machine: unlockMachine)
    precondition(state.capabilitiesWritten && !state.isBorrowed && state.cacheDataBitsReady)
    precondition(staged.cacheExtra[DictationRepairRestore.productType] as? String == unlockMachine,
                 "capability-only stage 1 never touches identity")
    precondition(staged.cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL")
    precondition(staged.cacheExtra[SiriAIYumUnlock.regionKey] as? String == "LL/A")
    precondition(staged.cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == "A2846",
                 "the regulatory model is never rewritten")
    let originalIdentity = SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: plain)
    precondition(originalIdentity.isEqual(SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: staged)),
                 "capability-only stage 1 leaves every identity key unchanged")

    // Stage 1 with the optional ProductType-only borrow.
    let borrowed = try SiriAIYumUnlock.stageOne(
        plist: plain, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: "iPhone18,5")
    precondition(borrowed.cacheExtra[DictationRepairRestore.productType] as? String == "iPhone18,5")
    precondition(borrowed.cacheExtra[DictationRepairRestore.hardwareModel] as? String == unlockBoard,
                 "the borrow never touches the board")
    precondition(borrowed.cacheExtra[DictationRepairRestore.cpuModel] as? String == unlockCPU,
                 "the borrow never touches the CPU")
    precondition(borrowed.cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == "A2846")

    // Error paths.
    func expectStageOneError(_ plist: GestaltPlist, borrow: String? = nil, _ error: SiriAIUnlockError) {
        do {
            _ = try SiriAIYumUnlock.stageOne(
                plist: plist, machine: unlockMachine,
                expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: borrow)
            fatalError("Expected \(error) from stage 1")
        } catch let thrown as SiriAIUnlockError {
            precondition(thrown == error, "Expected \(error), got \(thrown)")
        } catch {
            fatalError("Unexpected error type: \(error)")
        }
    }
    expectStageOneError(unlockCache(product: "iPhone16,1"), .identitySpoofed)
    expectStageOneError(unlockCache(board: "D83AP"), .identityMismatch)
    expectStageOneError(unlockCache(country: "CH", region: "CH"), .regionInconsistent)
    expectStageOneError(unlockCache(cacheData: Data([1, 2, 3])), .unknownCacheDataLayout)
    var missingData = unlockCache()
    missingData.dict.removeValue(forKey: SiriAIYumUnlock.cacheDataKey)
    expectStageOneError(missingData, .cacheDataMissing)
    expectStageOneError(try SiriAIYumUnlock.stageOne(
        plist: plain, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil), .alreadyComplete)
    expectStageOneError(unlockCache(), borrow: "iPhone99,9", .unknownBorrowProfile)

    // A CH device converts to LL as part of stage 1 (YumEdit semantics).
    let china = try SiriAIYumUnlock.stageOne(
        plist: unlockCache(country: "CH"), machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil)
    precondition(china.cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL")
    precondition(china.cacheExtra[SiriAIYumUnlock.regionKey] as? String == "LL/A")

    // A stock cache can carry no region pair at all. The region a device is
    // already in is never a precondition: stage 1 writes it. This is the case
    // that blocked Apply on a stock US iPhone 15.
    var stock = unlockCache()
    var stockExtra = stock.cacheExtra
    stockExtra.removeValue(forKey: SiriAIYumUnlock.countryKey)
    stockExtra.removeValue(forKey: SiriAIYumUnlock.regionKey)
    stock.cacheExtra = stockExtra
    precondition(SiriAIYumUnlock.blockingReasons(
        plist: stock, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        borrowProduct: nil).isEmpty,
        "a cache without region keys must not block stage 1")
    let stocked = try SiriAIYumUnlock.stageOne(
        plist: stock, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil)
    precondition(stocked.cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL")
    precondition(stocked.cacheExtra[SiriAIYumUnlock.regionKey] as? String == "LL/A")

    // Half a pair present is equally fine.
    var halfPair = unlockCache()
    var halfExtra = halfPair.cacheExtra
    halfExtra.removeValue(forKey: SiriAIYumUnlock.regionKey)
    halfPair.cacheExtra = halfExtra
    let halfStaged = try SiriAIYumUnlock.stageOne(
        plist: halfPair, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil)
    precondition(halfStaged.cacheExtra[SiriAIYumUnlock.regionKey] as? String == "LL/A")

    // A consistent US pair converts to LL like any other region.
    let us = try SiriAIYumUnlock.stageOne(
        plist: unlockCache(country: "US"), machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: nil)
    precondition(us.cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL")

    // A contradictory pair stays refused, and the preconditions say so
    // before Apply instead of after it.
    precondition(!SiriAIYumUnlock.blockingReasons(
        plist: unlockCache(country: "CH", region: "CH"), machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        borrowProduct: nil).isEmpty)
    precondition(!SiriAIYumUnlock.blockingReasons(
        plist: unlockCache(product: "iPhone16,1"), machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        borrowProduct: nil).isEmpty)
    var noCacheData = unlockCache()
    noCacheData.dict.removeValue(forKey: SiriAIYumUnlock.cacheDataKey)
    precondition(!SiriAIYumUnlock.blockingReasons(
        plist: noCacheData, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        borrowProduct: nil).isEmpty)
}
print("Passed: stage 1 writes capabilities + gate, borrows ProductType only, accepts a stock cache without a region pair, and refuses spoofed, mismatched, contradictory or unknown layouts.")

// MARK: - Stage 2: trusted backup provenance + identity restore

do {
    let originalData = Data(count: 0xFC8 + 8)
    let patchedData = try CacheDataUnlock.patch(originalData)
    let preUnlock = unlockCache(cacheData: originalData)  // real identity, closed gate
    let borrowed = try SiriAIYumUnlock.stageOne(
        plist: preUnlock, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU, borrowProduct: "iPhone18,5")
    precondition(borrowed.dict[SiriAIYumUnlock.cacheDataKey] as? Data == patchedData)

    // Trusted selection: same CacheUUID, provenance, physical identity.
    let trusted = SiriAIYumUnlock.trustedIdentitySource(
        current: borrowed, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        backups: [preUnlock])
    precondition(trusted != nil, "the pre-stage-1 backup must be trusted")

    // A wrong CacheUUID or a foreign identity is rejected.
    var foreignUUID = preUnlock
    foreignUUID.setValue("UUID-OTHER", forKey: SiriAIYumUnlock.cacheUUIDKey)
    precondition(SiriAIYumUnlock.trustedIdentitySource(
        current: borrowed, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        backups: [foreignUUID]) == nil)
    let foreignDevice = unlockCache(product: "iPhone14,5", board: "D17AP", cpu: "t8110")
    precondition(SiriAIYumUnlock.trustedIdentitySource(
        current: borrowed, machine: unlockMachine,
        expectedBoard: unlockBoard, expectedCPU: unlockCPU,
        backups: [foreignDevice]) == nil)

    // Stage 2 restores identity and keeps every capability write + the gate.
    let restored = try SiriAIYumUnlock.stageTwo(current: borrowed, identitySource: trusted!)
    let state = SiriAIYumUnlock.state(of: restored, machine: unlockMachine)
    precondition(state.unlockActive, "stage 2 ends in the unlock-active state")
    precondition(restored.cacheExtra[DictationRepairRestore.productType] as? String == unlockMachine)
    precondition(restored.cacheExtra[SiriAIYumUnlock.siriModeKey] as? Int == 2)
    precondition(restored.cacheExtra[SiriAIYumUnlock.generativeCapabilityKey] as? Int == 1)
    precondition(restored.cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL")
    precondition(restored.dict[SiriAIYumUnlock.cacheDataKey] as? Data == patchedData,
                 "stage 2 keeps the open CacheData gate")

    // The fork's old full borrow wrote extra identity fragments; stage 2
    // removes every fragment the backup does not carry.
    var legacyBorrowed = borrowed
    legacyBorrowed.setCacheExtra("D83AP", forKey: DictationRepairRestore.hardwareModelStr)
    legacyBorrowed.setCacheExtra("iPhone 15 Pro", forKey: DictationRepairRestore.marketingName)
    let legacyRestored = try SiriAIYumUnlock.stageTwo(current: legacyBorrowed, identitySource: trusted!)
    precondition(legacyRestored.cacheExtra[DictationRepairRestore.hardwareModelStr] == nil,
                 "borrow fragments absent from the backup are removed")
    precondition(legacyRestored.cacheExtra[DictationRepairRestore.marketingName] == nil)

    // Not borrowed → refuse.
    do {
        _ = try SiriAIYumUnlock.stageTwo(current: preUnlock, identitySource: trusted!)
        fatalError("Expected stage 2 to refuse an unborrowed cache")
    } catch let thrown as SiriAIUnlockError {
        precondition(thrown == .notBorrowed)
    } catch {
        fatalError("Unexpected error type: \(error)")
    }

    // The pre-unlock CacheData for a full revert comes from the same backup.
    precondition(SiriAIYumUnlock.originalCacheData(current: restored, backups: [preUnlock]) == originalData)
}
print("Passed: stage 2 restores identity from the trusted provenance-checked backup and keeps capabilities + gate.")

// MARK: - Device Doctor understands the two-stage states

do {
    let machine = "iPhone14,5"
    let gateData = try CacheDataUnlock.patch(Data(count: 0xFC8 + 8))
    let stageTwoCache: [String: Any] = [
        "h9jDsbgj7xIVeIQ8S3/X3Q": machine,
        "0+nc/Udy4WNG8S+Q7a/s1A": machine,
        "9s45ldrCC1WF+7b6C4H2BA": "iPhone",
        "oYicEKzVTz4/CxxE05pEgQ": "D17AP",
        "/YYygAofPDbhrwToVsXdeA": "D17AP",
        "5pYKlGnYYBzGvAlIU8RjEQ": "t8110",
        "Z/dqyWS6OZTRy10UcmUAhw": "iPhone 13",
        "bbtR9jQx50Fv5Af/affNtA": "iPhone 13",
        SiriAIYumUnlock.countryKey: "LL",
        SiriAIYumUnlock.regionKey: "LL/A",
        SiriAIYumUnlock.siriModeKey: 2,
        SiriAIYumUnlock.generativeCapabilityKey: 1,
    ]
    let stageTwoPlist = GestaltPlist(dict: ["CacheExtra": stageTwoCache, "CacheData": gateData])
    let stageTwoReport = DeviceIdentityAudit.audit(
        stageTwoPlist, machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil)
    precondition(stageTwoReport.isStageTwoUnlockActive, "finished unlock must be recognized")
    precondition(stageTwoReport.reportText.contains("SIRI AI UNLOCK ACTIVE"))
    precondition(stageTwoReport.reportText.contains("READY (unlocked)"))
    precondition(stageTwoReport.cacheDataBitsReady)

    // The same keys with a closed gate are plain residue, not an active unlock.
    let closedPlist = GestaltPlist(dict: ["CacheExtra": stageTwoCache, "CacheData": Data(count: 0xFC8 + 8)])
    let closedReport = DeviceIdentityAudit.audit(
        closedPlist, machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil)
    precondition(!closedReport.isStageTwoUnlockActive && closedReport.hasSiriAIResidue)
    precondition(closedReport.reportText.contains("NOT PATCHED"))

    // Stage-1 borrow: spoofed identity + AI keys → borrow-active verdict.
    var stageOneCache = stageTwoCache
    stageOneCache["h9jDsbgj7xIVeIQ8S3/X3Q"] = "iPhone18,5"
    let stageOnePlist = GestaltPlist(dict: ["CacheExtra": stageOneCache, "CacheData": gateData])
    let stageOneReport = DeviceIdentityAudit.audit(
        stageOnePlist, machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil)
    precondition(stageOneReport.isSpoofed && stageOneReport.hasSiriAIResidue)
    precondition(stageOneReport.reportText.contains("STAGE 1 BORROW ACTIVE"))
}
print("Passed: Device Doctor recognizes stage-1 borrow, stage-2 unlock and the CacheData gate state.")
// Repair restores the complete hardware identity plus the on-device Siri
// capability while AI flags, SiriMode, region and later edits stay enabled.
do {
    let original = GestaltPlist(dict: ["CacheExtra": [
        "0+nc/Udy4WNG8S+Q7a/s1A": "iPhone15,4",
        "h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4",
        "oYicEKzVTz4/CxxE05pEgQ": "D37AP",
        "5pYKlGnYYBzGvAlIU8RjEQ": "t8120",
        "97JDvERpVwO+GHtthIh7hA": "A3094",
        "K/R1GfGfCkXvEhaPS2Vrng": 3,
        "h63QSdBCiT/z0WU6rdQv6Q": "CH"
    ]])
    var broken = original
    broken.setCacheExtra("iPhone16,1", forKey: "h9jDsbgj7xIVeIQ8S3/X3Q")
    broken.setCacheExtra("D83AP", forKey: "oYicEKzVTz4/CxxE05pEgQ")
    broken.setCacheExtra("t8130", forKey: "5pYKlGnYYBzGvAlIU8RjEQ")
    broken.setCacheExtra("A2848", forKey: "97JDvERpVwO+GHtthIh7hA")
    broken.setCacheExtra(1, forKey: "A62OafQ85EJAiiqKn4agtg")
    broken.setCacheExtra(2, forKey: "a3n5T9sFtlyQ74NEp9ESxg")
    broken.setCacheExtra("LL", forKey: "h63QSdBCiT/z0WU6rdQv6Q")
    broken.setCacheExtra(1, forKey: "K/R1GfGfCkXvEhaPS2Vrng")
    broken.setCacheExtra("keep-later-edit", forKey: "unrelated")
    let repaired = DictationRepairRestore.restoring(broken, from: original)
    precondition(DictationRepairRestore.values(in: repaired).isEqual(DictationRepairRestore.values(in: original)))
    precondition(repaired.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1)
    precondition(repaired.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(repaired.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "LL")
    precondition(repaired.cacheExtra["unrelated"] as? String == "keep-later-edit")

    // Keys absent in the repair source are removed instead of guessed.
    let bareOriginal = GestaltPlist(dict: ["CacheExtra": ["0+nc/Udy4WNG8S+Q7a/s1A": "iPhone15,4"]])
    var overridden = bareOriginal
    overridden.setCacheExtra(1, forKey: "K/R1GfGfCkXvEhaPS2Vrng")
    overridden.setCacheExtra("iPhone16,1", forKey: "h9jDsbgj7xIVeIQ8S3/X3Q")
    let bareRepaired = DictationRepairRestore.restoring(overridden, from: bareOriginal)
    precondition(bareRepaired.cacheExtra["K/R1GfGfCkXvEhaPS2Vrng"] == nil)
    precondition(bareRepaired.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] == nil)

    // The repair source must describe the physical device. Spoofed, foreign,
    // suffixed or missing identities are only accepted when they match.
    let physical = GestaltPlist(dict: ["CacheExtra": ["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4"]])
    precondition(DictationRepairRestore.matchesPhysicalDevice(physical, machine: "iPhone15,4"))
    precondition(DictationRepairRestore.matchesPhysicalDevice(
        GestaltPlist(dict: ["CacheExtra": ["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4-A"]]), machine: "iPhone15,4"))
    var spoofedSource = physical
    spoofedSource.setCacheExtra("iPhone16,1", forKey: "h9jDsbgj7xIVeIQ8S3/X3Q")
    precondition(!DictationRepairRestore.matchesPhysicalDevice(spoofedSource, machine: "iPhone15,4"))
    precondition(!DictationRepairRestore.matchesPhysicalDevice(physical, machine: "iPhone15,2"))
    precondition(!DictationRepairRestore.matchesPhysicalDevice(GestaltPlist(dict: ["CacheExtra": [:]]), machine: "iPhone15,4"))
    precondition(!DictationRepairRestore.matchesPhysicalDevice(physical, machine: ""))
}
print("Passed: dictation repair restores identity and on-device Siri capability, keeps AI settings and rejects spoofed sources.")

// MARK: - Device Identity Doctor (scan + fix plan + apply)

do {
    let machine = "iPhone14,5"
    let cleanIdentity: [String: Any] = [
        "h9jDsbgj7xIVeIQ8S3/X3Q": machine,
        "0+nc/Udy4WNG8S+Q7a/s1A": machine,
        // GS Device Name is the device FAMILY name on stock caches, never the
        // machine identifier (v2.6.2 regression fix).
        "9s45ldrCC1WF+7b6C4H2BA": "iPhone",
        "oYicEKzVTz4/CxxE05pEgQ": "D17AP",
        "/YYygAofPDbhrwToVsXdeA": "D17AP",
        "5pYKlGnYYBzGvAlIU8RjEQ": "t8110",
        "97JDvERpVwO+GHtthIh7hA": "A2633",
        "Z/dqyWS6OZTRy10UcmUAhw": "iPhone 13",
        "bbtR9jQx50Fv5Af/affNtA": "iPhone 13",
    ]

    // A cache spoofed by an earlier editor (three identity keys faked) must be
    // detected against the kernel's machine identifier and IOKit platform.
    var spoofedExtra = cleanIdentity
    spoofedExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] = "iPhone16,1"
    spoofedExtra["0+nc/Udy4WNG8S+Q7a/s1A"] = "iPhone16,1"
    spoofedExtra["oYicEKzVTz4/CxxE05pEgQ"] = "D83AP"
    spoofedExtra["5pYKlGnYYBzGvAlIU8RjEQ"] = "t8130"
    spoofedExtra["Z/dqyWS6OZTRy10UcmUAhw"] = "iPhone 15 Pro"
    spoofedExtra["K/R1GfGfCkXvEhaPS2Vrng"] = 1
    spoofedExtra["97JDvERpVwO+GHtthIh7hA"] = "not-a-model"
    spoofedExtra["A62OafQ85EJAiiqKn4agtg"] = 1
    spoofedExtra["a3n5T9sFtlyQ74NEp9ESxg"] = 2

    let report = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": spoofedExtra]),
        machine: machine,
        kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110",
        backupIdentity: nil
    )
    precondition(report.isSpoofed, "Spoofed cache must be detected")
    precondition(report.spoofedEntries.count >= 6,
                 "Expected product/board/cpu/name/regulatory mismatches, got \(report.spoofedEntries.map { $0.title })")
    precondition(report.hasSiriAIResidue, "AI keys stored alongside a spoof are also residue")
    precondition(!report.reportText.isEmpty)

    // Fix plan: every proposal must restore the hardware-reported values.
    var plan = DeviceIdentityAudit.fixPlan(from: report, removeSiriOnDevice: false, regulatoryModelOverride: nil)
    precondition(plan.hasChanges)
    precondition(plan.proposals.contains { $0.id == "h9jDsbgj7xIVeIQ8S3/X3Q" && $0.proposedValue == machine })
    precondition(plan.proposals.contains { $0.id == "5pYKlGnYYBzGvAlIU8RjEQ" && $0.proposedValue == "t8110" })
    // The broken regulatory value cannot be guessed: only the user override adds it.
    precondition(!plan.proposals.contains { $0.id == "97JDvERpVwO+GHtthIh7hA" })
    plan = DeviceIdentityAudit.fixPlan(from: report, removeSiriOnDevice: true, regulatoryModelOverride: "A2633")
    precondition(plan.proposals.contains { $0.id == "97JDvERpVwO+GHtthIh7hA" && $0.proposedValue == "A2633" })
    precondition(plan.proposals.contains { $0.id == "K/R1GfGfCkXvEhaPS2Vrng" && $0.isRemoval })

    // Applying the plan must leave a cache the doctor considers clean, with
    // AI capability flags untouched.
    var applied = GestaltPlist(dict: ["CacheExtra": spoofedExtra])
    DeviceIdentityAudit.applying(plan, to: &applied)
    precondition(applied.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1)
    precondition(applied.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(applied.cacheExtra["K/R1GfGfCkXvEhaPS2Vrng"] == nil)
    let recheck = DeviceIdentityAudit.audit(
        applied, machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!recheck.isSpoofed, "Post-fix cache must audit clean")

    // A clean cache audits clean without any proposal.
    let cleanReport = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": cleanIdentity]),
        machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!cleanReport.isSpoofed)
    precondition(!DeviceIdentityAudit.fixPlan(from: cleanReport, removeSiriOnDevice: false, regulatoryModelOverride: nil).hasChanges)
    // v2.6.2: the doctor compares GS Device Name against the device family the
    // kernel reports — the machine-identifier comparison verdicted healthy
    // caches as "spoofed" and the fix plan would have rewritten them.
    precondition(DeviceIdentityAudit.deviceFamily(for: "iPhone15,4") == "iPhone")
    precondition(DeviceIdentityAudit.deviceFamily(for: "iPad16,1") == "iPad")
    precondition(DeviceIdentityAudit.deviceFamily(for: "iPod9,4") == "iPod")

    // Backup truth is used when the kernel cannot answer a key (no IOKit).
    let backupReport = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": spoofedExtra]),
        machine: machine, kernelHardwareModel: nil,
        ioKitPlatform: nil,
        backupIdentity: NSDictionary(dictionary: cleanIdentity)
    )
    precondition(backupReport.isSpoofed)
    let backupPlan = DeviceIdentityAudit.fixPlan(from: backupReport, removeSiriOnDevice: false, regulatoryModelOverride: nil)
    precondition(backupPlan.proposals.contains { $0.id == "oYicEKzVTz4/CxxE05pEgQ" && $0.proposedValue == "D17AP" })

    // Repair acceptance: a clean backup matches the physical device even
    // though the live cache is spoofed (the doctor's core scenario).
    let cleanPlist = GestaltPlist(dict: ["CacheExtra": cleanIdentity])
    precondition(DictationRepairRestore.matchesPhysicalDevice(cleanPlist, machine: machine))
    precondition(!DictationRepairRestore.matchesPhysicalDevice(
        GestaltPlist(dict: ["CacheExtra": spoofedExtra]), machine: machine))
    // Nugget-style tools spoof ThinningProductType only: still detected.
    var thinningSpoof = cleanIdentity
    thinningSpoof["0+nc/Udy4WNG8S+Q7a/s1A"] = "iPhone16,1"
    precondition(!DictationRepairRestore.matchesPhysicalDevice(
        GestaltPlist(dict: ["CacheExtra": thinningSpoof]), machine: machine))

    // Validation helpers.
    precondition(DeviceIdentityAudit.validBoard("D17AP") == "D17AP")
    precondition(DeviceIdentityAudit.validBoard("D52gAP") == "D52gAP")
    precondition(DeviceIdentityAudit.validBoard("D331pAP") == "D331pAP")
    precondition(DeviceIdentityAudit.validBoard("V64sAP") == "V64sAP")
    precondition(DeviceIdentityAudit.validBoard("iPhone14,5") == nil)
    precondition(DeviceIdentityAudit.validBoard("garbage") == nil)
    precondition(DeviceIdentityAudit.validPlatform("t8110") == "t8110")
    precondition(DeviceIdentityAudit.validPlatform("t8140a") == "t8140a")
    precondition(DeviceIdentityAudit.validPlatform("iPhone14,5") == nil)
    precondition(DeviceIdentityAudit.validPlatform("t8108x9") == nil)
    precondition(DeviceIdentityAudit.validRegulatory("A2633"))
    precondition(!DeviceIdentityAudit.validRegulatory("MYD03LL/A"))
    precondition(!DeviceIdentityAudit.validRegulatory("not-a-model"))
}
print("Passed: Device Doctor detects spoofs with or without backups, plans hardware-verified fixes and keeps AI flags.")

// MARK: - Device Doctor v2 (Siri AI residue scan, residue-only fix, inventory)

// The exact state behind "Identity Matches This Device" but dictation still
// broken: identity is clean, yet Siri AI activation keys and the LL region
// override written by an earlier editor are still stored.
do {
    let machine = "iPhone14,5"
    let residueExtra: [String: Any] = [
        "h9jDsbgj7xIVeIQ8S3/X3Q": machine,
        "0+nc/Udy4WNG8S+Q7a/s1A": machine,
        "9s45ldrCC1WF+7b6C4H2BA": "iPhone",  // family name, as on stock devices
        "oYicEKzVTz4/CxxE05pEgQ": "D17AP",
        "/YYygAofPDbhrwToVsXdeA": "D17AP",
        "5pYKlGnYYBzGvAlIU8RjEQ": "t8110",
        "97JDvERpVwO+GHtthIh7hA": "A2633",
        "Z/dqyWS6OZTRy10UcmUAhw": "iPhone 13",
        "bbtR9jQx50Fv5Af/affNtA": "iPhone 13",
        "A62OafQ85EJAiiqKn4agtg": 1,
        "a3n5T9sFtlyQ74NEp9ESxg": 2,
        "eX0KGm4RpWq7bZV1tY8s3A": 1,
        "4pPl3nt3LL1g3nc3All0wd": true,
        "4pPl3nt3LL1g3nc3Supptd": true,
        "4pPl3nt3LL1g3nc3M1nRAm": 6,
        "h63QSdBCiT/z0WU6rdQv6Q": "LL",
        "yK+xavymRGZ3xWc1tb8XDg": "LL/A",
        "zHeENZu+wbg7PUprwNwBWg": "LL/A",
        "unrelated-key": "keep",
    ]
    let residueReport = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": residueExtra]),
        machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!residueReport.isSpoofed, "identity keys are clean")
    precondition(residueReport.hasSiriAIResidue, "AI keys must be reported as residue")
    precondition(residueReport.siriAIResidueEntries.count == 6,
                 "capability, SiriMode, expansion flag and the persistence triple are residue")
    precondition(residueReport.siriAIResidueEntries.allSatisfy { $0.status == .residue })
    precondition(residueReport.regionOverrideEntries.count == 3, "LL/LL/A region values surface as residue")
    precondition(residueReport.identityEntries.count == residueReport.entries.count - 9)
    precondition(residueReport.cacheKeyCount == 19)
    precondition(residueReport.cacheInventoryText.contains("unrelated-key = keep"),
                 "inventory lists every stored key")
    precondition(residueReport.reportText.contains("Siri AI activation keys are still stored"))
    precondition(residueReport.reportText.contains("re-downloads fresh speech resources"),
                 "residue verdict points to the per-language speech-asset refresh")

    // Default plan leaves the cache alone; opting in removes exactly the
    // activation keys and region overrides and nothing else.
    let defaultPlan = DeviceIdentityAudit.fixPlan(from: residueReport)
    precondition(!defaultPlan.hasChanges)
    let plan = DeviceIdentityAudit.fixPlan(
        from: residueReport, removeSiriAIKeys: true, removeRegionOverrides: true)
    precondition(plan.proposals.allSatisfy { $0.isRemoval })
    // siriAIKeys covers every residue key the doctor can clean (including the
    // v2.9.0 experimental toggles); the fixture only stores the original six,
    // so the proposals are a subset of the full cleanup key set.
    precondition(plan.proposals.count ==
                 Set(residueExtra.keys.filter { DeviceIdentityAudit.siriAIKeys.contains($0) }).count + 3)
    precondition(Set(plan.proposals.map(\.id)).isSubset(of:
                 Set(DeviceIdentityAudit.siriAIKeys + DeviceIdentityAudit.regionOverrideKeys)))
    var applied = GestaltPlist(dict: ["CacheExtra": residueExtra])
    DeviceIdentityAudit.applying(plan, to: &applied)
    precondition(applied.cacheExtra["A62OafQ85EJAiiqKn4agtg"] == nil)
    precondition(applied.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] == nil)
    precondition(applied.cacheExtra["eX0KGm4RpWq7bZV1tY8s3A"] == nil)
    precondition(applied.cacheExtra["4pPl3nt3LL1g3nc3All0wd"] == nil)
    precondition(applied.cacheExtra["4pPl3nt3LL1g3nc3Supptd"] == nil)
    precondition(applied.cacheExtra["4pPl3nt3LL1g3nc3M1nRAm"] == nil)
    precondition(applied.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] == nil)
    precondition(applied.cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] == nil)
    precondition(applied.cacheExtra["zHeENZu+wbg7PUprwNwBWg"] == nil)
    precondition(applied.cacheExtra["unrelated-key"] as? String == "keep")
    let recheck = DeviceIdentityAudit.audit(
        applied, machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!recheck.hasSiriAIResidue, "post-fix cache must be residue-free")

    // Non-LL region values are genuine and are never reported as residue;
    // a cache without activation keys audits fully clean.
    var genuine = residueExtra
    genuine["h63QSdBCiT/z0WU6rdQv6Q"] = "CH"
    genuine["yK+xavymRGZ3xWc1tb8XDg"] = "CH/A"
    genuine["zHeENZu+wbg7PUprwNwBWg"] = "CH/A"
    for key in ["A62OafQ85EJAiiqKn4agtg", "a3n5T9sFtlyQ74NEp9ESxg",
                "eX0KGm4RpWq7bZV1tY8s3A",
                "4pPl3nt3LL1g3nc3All0wd",
                "4pPl3nt3LL1g3nc3Supptd",
                "4pPl3nt3LL1g3nc3M1nRAm"] {
        genuine.removeValue(forKey: key)
    }
    let genuineReport = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": genuine]),
        machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!genuineReport.hasSiriAIResidue)
    precondition(genuineReport.regionOverrideEntries.isEmpty)
    precondition(genuineReport.reportText.contains("cache is clean"))
    precondition(genuineReport.reportText.contains("works in one language but fails in another"),
                 "clean verdict includes the per-language speech-asset triage")
}
print("Passed: Device Doctor v2 residue scan, residue-only fix plan and full cache inventory.")

// Factory cache reset: clearCacheExtra leaves nothing behind for iOS to
// rebuild from, while the rest of the plist stays intact.
do {
    var cache = GestaltPlist(dict: [
        "CacheExtra": ["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone16,1", "A62OafQ85EJAiiqKn4agtg": 1],
        "CacheData": Data([1, 2, 3]),
    ])
    cache.clearCacheExtra()
    precondition(cache.cacheExtra.isEmpty)
    precondition(cache.dict["CacheData"] as? Data == Data([1, 2, 3]))
    let report = DeviceIdentityAudit.audit(
        cache, machine: "iPhone14,5", kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!report.isSpoofed && !report.hasSiriAIResidue && report.cacheKeyCount == 0)
}
print("Passed: factory cache reset clears CacheExtra and audits clean.")

// MARK: - AI Feature Eligibility override (GreyMatter/Calcium)

do {
    let override = AIEligibilityOverride.overridePlist(languageCodes: ["en-US", "en-NZ"])
    let grey = override["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any]
    let calcium = override["OS_ELIGIBILITY_DOMAIN_CALCIUM"] as? [String: Any]
    precondition(grey != nil && calcium != nil)
    precondition((grey?["os_eligibility_answer_source_t"] as? Int) == 1, "override source")
    precondition((grey?["os_eligibility_answer_t"] as? Int) == 4, "pending-asset answer")
    let status = grey?["status"] as? [String: Int]
    precondition(status?["OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM"] == 3,
                 "the A16-blocking input is definitely-satisfied")
    precondition(status?["OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE"] == 3)
    precondition(status?["OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE"] == 3)
    let context = grey?["context"] as? [String: Any]
    precondition((context?["OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES"] as? [String]) == ["en", "en-US", "en-NZ"],
                 "en is always included, then the configured codes in order")
    precondition((calcium?["status"] as? [String: Int])?["OS_ELIGIBILITY_INPUT_CHINA_CELLULAR"] == 2)

    precondition(AIEligibilityOverride.isApplied(override))
    precondition(!AIEligibilityOverride.isApplied([:]))

    // Merging preserves foreign domains and replaces ours.
    let existing: [String: Any] = [
        "OS_ELIGIBILITY_DOMAIN_SOMETHINGELSE": ["keep": 1],
        "OS_ELIGIBILITY_DOMAIN_GREYMATTER": ["stale": true],
    ]
    let merged = AIEligibilityOverride.merged(into: existing, languageCodes: ["en-US"])
    precondition((merged["OS_ELIGIBILITY_DOMAIN_SOMETHINGELSE"] as? [String: Any])?["keep"] as? Int == 1)
    precondition((merged["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any])?["os_eligibility_answer_source_t"] as? Int == 1)

    // A non-domain-shaped file is replaced, not merged into.
    let replaced = AIEligibilityOverride.merged(into: ["garbage": true], languageCodes: ["en-US"])
    precondition(replaced["garbage"] == nil && replaced["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] != nil)
}
print("Passed: AI eligibility override structure, applied detection and merge semantics.")

// MARK: - CacheData cell scanner + single-bit flip

do {
    var blob = Data(count: 0x1000)
    // On a zero-filled blob the 0xBF0 cell (target 0) is already satisfied,
    // so the gate only needs the two 1-cells — model the China-restriction
    // cell as closed-at-1 first to exercise all three cells.
    blob[0xBF0] = 1
    blob = try CacheDataUnlock.setBit(blob, offset: 0x720, value: 1)
    blob = try CacheDataUnlock.setBit(blob, offset: 0xFC8, value: 1)
    precondition(CacheDataUnlock.bitsReady(blob) == false,
                 "two of three gate cells are not the full unlock")
    let active = CacheDataScanner.activeCells(blob)
    precondition(active.map(\.offset) == [0x720, 0xBF0, 0xFC8], "active cells detected on 8-byte boundaries")
    let suggested = CacheDataScanner.suggestedCandidates(blob)
    precondition(suggested.contains { $0.offset == 0x728 },
                 "zero siblings within 64 bytes of an active cell are suggested")
    precondition(!suggested.contains { $0.offset == 0xF00 }, "distant zero runs are not suggested")

    // Flip back and forth through setBit.
    blob = try CacheDataUnlock.setBit(blob, offset: 0x720, value: 0)
    blob = try CacheDataUnlock.setBit(blob, offset: 0xBF0, value: 0)
    blob = try CacheDataUnlock.setBit(blob, offset: 0xFC8, value: 0)
    precondition(CacheDataUnlock.bitsReady(blob) == false, "all three cells closed re-closes the gate")
    blob = try CacheDataUnlock.setBit(blob, offset: 0x720, value: 1)
    blob = try CacheDataUnlock.setBit(blob, offset: 0xBF0, value: 0)
    blob = try CacheDataUnlock.setBit(blob, offset: 0xFC8, value: 1)
    precondition(CacheDataUnlock.bitsReady(blob), "the complete gate sequence reads ready")
    precondition(CacheDataScanner.activeCells(blob).map(\.offset) == [0x720, 0xFC8])
    do {
        _ = try CacheDataUnlock.setBit(blob, offset: 0x728, value: 2)
        fatalError("Expected a non-boolean value to fail")
    } catch { }
    var contaminated = blob
    contaminated[0x729] = 9
    do {
        _ = try CacheDataUnlock.setBit(contaminated, offset: 0x728, value: 1)
        fatalError("Expected a contaminated cell to fail")
    } catch { }
}
print("Passed: CacheData cell scanner finds active + sibling cells and setBit validates every flip.")

// MARK: - Experimental AI capability keys

do {
    precondition(ExperimentalAICapabilities.keys.contains {
        $0.key == "8Vbp0HyqndjWuIFZibhu7g" && $0.name == "DeviceSupportsGrey"
    }, "the GreyMatter device flag is in the experimental set")
    precondition(ExperimentalAICapabilities.keys.contains {
        $0.key == "I3lidq+FVH2CeOi/ARa0tg"
    }, "the second generative-model-systems flag is in the experimental set")
    precondition(ExperimentalAICapabilities.allKeys.count == ExperimentalAICapabilities.keys.count)
    precondition(ExperimentalAICapabilities.allKeys.contains("K/R1GfGfCkXvEhaPS2Vrng"),
                 "the on-device Siri understanding key IS part of the experimental set")

    // Reconcile semantics: selected keys are forced to 1, unselected known
    // keys are removed, and unknown keys are untouched. Turning every field
    // off remains a detectable staged change.
    var cache: [String: Any] = [
        "8Vbp0HyqndjWuIFZibhu7g": 0,
        "K/R1GfGfCkXvEhaPS2Vrng": 1,
        "unrelated": "keep",
    ]
    let selected: Set<String> = ["8Vbp0HyqndjWuIFZibhu7g", "I3lidq+FVH2CeOi/ARa0tg"]
    precondition(ExperimentalAICapabilities.selectedKeys(in: cache)
        == ["K/R1GfGfCkXvEhaPS2Vrng"])
    precondition(ExperimentalAICapabilities.hasChanges(cache: cache, selected: selected))
    ExperimentalAICapabilities.reconcile(cache: &cache, selected: selected)
    precondition(cache["8Vbp0HyqndjWuIFZibhu7g"] as? Int == 1)
    precondition(cache["I3lidq+FVH2CeOi/ARa0tg"] as? Int == 1)
    precondition(cache["K/R1GfGfCkXvEhaPS2Vrng"] == nil, "unselected known key removed")
    precondition(cache["unrelated"] as? String == "keep")
    precondition(!ExperimentalAICapabilities.hasChanges(cache: cache, selected: selected))

    let allOff: Set<String> = []
    precondition(ExperimentalAICapabilities.hasChanges(cache: cache, selected: allOff),
                 "deselecting every key must still expose Apply")
    ExperimentalAICapabilities.reconcile(cache: &cache, selected: allOff)
    precondition(ExperimentalAICapabilities.allKeys.allSatisfy { cache[$0] == nil })
    precondition(cache["unrelated"] as? String == "keep")
}
print("Passed: experimental AI capability key set and reconcile semantics.")

// MARK: - OS Eligibility template (35 domains) + AI overlay merge

do {
    let data = EligibilityTemplate.decodedData
    precondition(data != nil, "the embedded eligibility template decodes")
    let template = (try? PropertyListSerialization.propertyList(
        from: data!, format: nil)) as? [String: Any]
    precondition(template != nil, "the template parses as a plist")
    let domainCount = (template!.keys.filter { $0.hasPrefix("OS_ELIGIBILITY_DOMAIN_") }).count
    precondition(domainCount == 35, "the template carries all 35 region domains, got \(domainCount)")
    precondition(template!["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] == nil,
                 "the region template has no AI domain — the AI overlay adds it")

    let merged = AIEligibilityOverride.merged(into: template, languageCodes: ["en-US"])
    let grey = merged["OS_ELIGIBILITY_DOMAIN_GREYMATTER"] as? [String: Any]
    precondition(grey != nil && (grey?["os_eligibility_answer_source_t"] as? Int) == 1,
                 "the AI overlay adds GREYMATTER to the region template")
    precondition((merged["OS_ELIGIBILITY_DOMAIN_CALCIUM"] as? [String: Any]) != nil)
    let kept = (merged.keys.filter { $0.hasPrefix("OS_ELIGIBILITY_DOMAIN_") }).count
    precondition(kept == 37, "35 region domains + GREYMATTER + CALCIUM = 37, got \(kept)")
}
print("Passed: eligibility template decodes, carries 35 region domains, and the AI overlay merges onto it.")

// MARK: - Classic Apple Intelligence enabler (single key)

do {
    let plain = GestaltPlist(dict: ["CacheExtra": ["unrelated": "keep"]])
    let enabled = SiriAIYumUnlock.classicEnable(plist: plain)
    precondition(enabled.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1,
                 "classic enabler writes the generative capability key")
    precondition(enabled.cacheExtra["unrelated"] as? String == "keep")
    precondition(enabled.cacheExtra[SiriAIYumUnlock.siriModeKey] == nil,
                 "classic mode never touches SiriMode — the expanded pipeline is what wedged")
    precondition(enabled.cacheExtra[SiriAIYumUnlock.cacheDataKey] == nil ||
                 enabled.dict[SiriAIYumUnlock.cacheDataKey] == nil,
                 "classic mode never patches CacheData")
    precondition(enabled.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] == nil,
                 "classic mode never borrows identity")

    let disabled = SiriAIYumUnlock.classicDisable(plist: enabled)
    precondition(disabled.cacheExtra["A62OafQ85EJAiiqKn4agtg"] == nil)
    precondition(disabled.cacheExtra["unrelated"] as? String == "keep")
}
print("Passed: classic enabler is the single-key iOS 18-26 advertisement, fully revertible.")
