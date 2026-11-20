import Foundation

// xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/GestaltTweaks.swift GestaltEdit/GestaltBackupStore.swift Tests/GestaltPresets/main.swift -o /tmp/gestalt-preset-tests
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

// Supported non-US regions retain all region/model fields, including absent
// fields. Only known regional restrictions trigger a device-region override.
for code in ["LL", "J", "TA", "ZA", "B", "C", "FD", "D", "F", "IP", "unknown"] {
    var device = GestaltPlist(dict: ["CacheExtra": [
        "0+nc/Udy4WNG8S+Q7a/s1A": "iPhone15,4",
        "h63QSdBCiT/z0WU6rdQv6Q": code,
        "yK+xavymRGZ3xWc1tb8XDg": code + "/A",
        "zHeENZu+wbg7PUprwNwBWg": code + "/A",
        "97JDvERpVwO+GHtthIh7hA": "keep-original-model"
    ]])
    let originalRegion = AIRegionConfiguration.regionValues(in: device)
    let configuration = AIRegionConfiguration.resolve(for: device, osMajorVersion: 27, mode: .temporarySpoof)
    precondition(!configuration.changesRegion)
    configuration.apply(to: &device)
    precondition(originalRegion.isEqual(AIRegionConfiguration.regionValues(in: device)))
    precondition(device.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(device.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String == "iPhone16,1")
}
do {
    var device = GestaltPlist(dict: ["CacheExtra": [
        "0+nc/Udy4WNG8S+Q7a/s1A": "iPhone16,1",
        "zHeENZu+wbg7PUprwNwBWg": "CH/A"
    ]])
    let configuration = AIRegionConfiguration.resolve(for: device, osMajorVersion: 27)
    precondition(configuration.changesRegion)
    configuration.apply(to: &device)
    precondition(device.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "LL")
    precondition(device.cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] as? String == "LL/A")
    precondition(device.cacheExtra["zHeENZu+wbg7PUprwNwBWg"] as? String == "LL/A")
    precondition(device.cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == "A2848")
}
for key in ["h63QSdBCiT/z0WU6rdQv6Q", "yK+xavymRGZ3xWc1tb8XDg", "zHeENZu+wbg7PUprwNwBWg"] {
    let device = GestaltPlist(dict: ["CacheExtra": [key: " ch/a "]])
    precondition(AIRegionConfiguration.resolve(for: device).changesRegion)
}
var missingRegion = GestaltPlist(dict: ["CacheExtra": [:]])
let missingConfig = AIRegionConfiguration.resolve(for: missingRegion, osMajorVersion: 27)
missingConfig.apply(to: &missingRegion)
precondition(AIRegionConfiguration.regionValues(in: missingRegion).count == 0)
print("Passed: Siri AI preserves supported/unknown regions and model values; only known restricted regions trigger adjustment.")

// Both absent and explicit original identity fields must survive a full
// setup -> download -> unspoof cycle. Recovery must preserve later edits.
for identity: [String: Any] in [[:], [
    "h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4",
    "oYicEKzVTz4/CxxE05pEgQ": "D37AP",
    "5pYKlGnYYBzGvAlIU8RjEQ": "t8120"
]] {
    var extra: [String: Any] = [
        "0+nc/Udy4WNG8S+Q7a/s1A": "iPhone15,4",
        "h63QSdBCiT/z0WU6rdQv6Q": "CH",
        "97JDvERpVwO+GHtthIh7hA": "original-model"
    ]
    extra.merge(identity) { _, new in new }
    let original = GestaltPlist(dict: ["CacheExtra": extra, "CacheData": Data([4, 5, 6])])
    let configuration = AIRegionConfiguration.resolve(for: original, osMajorVersion: 27, mode: .temporarySpoof)
    precondition(configuration.requiresDeviceSpoofing)
    var setup = original
    configuration.apply(to: &setup)
    precondition(setup.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1)
    precondition(setup.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(setup.cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String == "A2848")
    let specialSnapshot = SiriAIIdentityRestore.restoring(setup, from: original)
    var afterDownload = setup
    afterDownload.setCacheExtra("keep-later-edit", forKey: "unrelated")
    afterDownload.setCacheExtra("TA", forKey: "h63QSdBCiT/z0WU6rdQv6Q")
    let recovered = SiriAIIdentityRestore.restoring(afterDownload, from: specialSnapshot)
    precondition(SiriAIIdentityRestore.values(in: recovered).isEqual(SiriAIIdentityRestore.values(in: original)))
    precondition(recovered.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1)
    precondition(recovered.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(recovered.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "TA")
    precondition(recovered.cacheExtra["unrelated"] as? String == "keep-later-edit")
    precondition(recovered.dict["CacheData"] as? Data == original.dict["CacheData"] as? Data)
    precondition(SiriAIIdentityRestore.sameDevice(recovered, specialSnapshot))
    let anotherDevice = GestaltPlist(dict: ["CacheExtra": ["0+nc/Udy4WNG8S+Q7a/s1A": "iPhone14,6"]])
    precondition(!SiriAIIdentityRestore.sameDevice(anotherDevice, specialSnapshot))
}
let specialBackup = GestaltBackup(url: URL(fileURLWithPath: "/tmp/SiriAI_RestoreIdentity_AfterModelDownload_2026-11-16.plist"), createdAt: Date(), byteCount: 0)
precondition(specialBackup.purpose == .siriAIIdentityRestore)
precondition(specialBackup.displayTitle != nil)
let ordinaryBackup = GestaltBackup(url: URL(fileURLWithPath: "/tmp/MobileGestalt_2026-11-16.plist"), createdAt: Date(), byteCount: 0)
precondition(ordinaryBackup.purpose == .standard && ordinaryBackup.displayTitle == nil)
print("Passed: temporary spoof setup, identity-only recovery, SiriMode=2 retention, unrelated-edit preservation and backup purpose recognition.")

// Dictation-safe activation (the default) writes only the Siri AI capability
// flags. Device identity, the regulatory model number, the on-device Siri
// capability type and CacheData must be identical before and after.
for identity: [String: Any] in [[:], [
    "h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone15,4",
    "oYicEKzVTz4/CxxE05pEgQ": "D37AP",
    "5pYKlGnYYBzGvAlIU8RjEQ": "t8120",
    "97JDvERpVwO+GHtthIh7hA": "A3094",
    "K/R1GfGfCkXvEhaPS2Vrng": 3
]] {
    var extra: [String: Any] = [
        "0+nc/Udy4WNG8S+Q7a/s1A": "iPhone15,4",
        "h63QSdBCiT/z0WU6rdQv6Q": "CH",
        "zHeENZu+wbg7PUprwNwBWg": "CH/A"
    ]
    extra.merge(identity) { _, new in new }
    let original = GestaltPlist(dict: ["CacheExtra": extra, "CacheData": Data([7, 8, 9])])
    let configuration = AIRegionConfiguration.resolve(for: original, osMajorVersion: 27)
    precondition(!configuration.requiresDeviceSpoofing)
    precondition(!configuration.usesTwoStageSetup)
    precondition(configuration.changesRegion)
    var setup = original
    configuration.apply(to: &setup)
    precondition(setup.cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1)
    precondition(setup.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2)
    precondition(setup.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "LL")
    precondition(setup.cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] as? String == "LL/A")
    precondition(setup.cacheExtra["zHeENZu+wbg7PUprwNwBWg"] as? String == "LL/A")
    precondition((setup.cacheExtra["97JDvERpVwO+GHtthIh7hA"] as? String) == identity["97JDvERpVwO+GHtthIh7hA"] as? String)
    precondition(SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: setup)
        .isEqual(SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: original)))
    precondition(setup.dict["CacheData"] as? Data == Data([7, 8, 9]))
}
print("Passed: dictation-safe activation preserves identity, regulatory model, on-device Siri capability and CacheData.")

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
        "9s45ldrCC1WF+7b6C4H2BA": machine,
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
        "9s45ldrCC1WF+7b6C4H2BA": machine,
        "oYicEKzVTz4/CxxE05pEgQ": "D17AP",
        "/YYygAofPDbhrwToVsXdeA": "D17AP",
        "5pYKlGnYYBzGvAlIU8RjEQ": "t8110",
        "97JDvERpVwO+GHtthIh7hA": "A2633",
        "Z/dqyWS6OZTRy10UcmUAhw": "iPhone 13",
        "bbtR9jQx50Fv5Af/affNtA": "iPhone 13",
        "A62OafQ85EJAiiqKn4agtg": 1,
        "a3n5T9sFtlyQ74NEp9ESxg": 2,
        "h63QSdBCiT/z0WU6rdQv6Q": "LL",
        "yK+xavymRGZ3xWc1tb8XDg": "LL/A",
        "unrelated-key": "keep",
    ]
    let residueReport = DeviceIdentityAudit.audit(
        GestaltPlist(dict: ["CacheExtra": residueExtra]),
        machine: machine, kernelHardwareModel: "D17AP",
        ioKitPlatform: "t8110", backupIdentity: nil
    )
    precondition(!residueReport.isSpoofed, "identity keys are clean")
    precondition(residueReport.hasSiriAIResidue, "AI keys must be reported as residue")
    precondition(residueReport.siriAIResidueEntries.count == 2)
    precondition(residueReport.siriAIResidueEntries.allSatisfy { $0.status == .residue })
    precondition(residueReport.regionOverrideEntries.count == 2, "LL/LL/A region values surface as residue")
    precondition(residueReport.identityEntries.count == residueReport.entries.count - 4)
    precondition(residueReport.cacheKeyCount == 14)
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
    precondition(Set(plan.proposals.map(\.id)) ==
                 Set(DeviceIdentityAudit.siriAIKeys + DeviceIdentityAudit.regionOverrideKeys))
    var applied = GestaltPlist(dict: ["CacheExtra": residueExtra])
    DeviceIdentityAudit.applying(plan, to: &applied)
    precondition(applied.cacheExtra["A62OafQ85EJAiiqKn4agtg"] == nil)
    precondition(applied.cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] == nil)
    precondition(applied.cacheExtra["h63QSdBCiT/z0WU6rdQv6Q"] == nil)
    precondition(applied.cacheExtra["yK+xavymRGZ3xWc1tb8XDg"] == nil)
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
    genuine.removeValue(forKey: "A62OafQ85EJAiiqKn4agtg")
    genuine.removeValue(forKey: "a3n5T9sFtlyQ74NEp9ESxg")
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
