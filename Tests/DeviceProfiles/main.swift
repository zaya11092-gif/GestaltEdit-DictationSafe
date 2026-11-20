import Foundation

// Run from the repository root:
// xcrun swiftc GestaltEdit/GestaltModels.swift Tests/DeviceProfiles/main.swift -o /tmp/gestalt-device-tests && /tmp/gestalt-device-tests
let productKey = "0+nc/Udy4WNG8S+Q7a/s1A"
let marketingKeys = ["Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"]
let newDevices = [
    ("iPhone18,1", "iPhone 17 Pro", "A3256"),
    ("iPhone18,2", "iPhone 17 Pro Max", "A3257"),
    ("iPhone18,3", "iPhone 17", "A3258"),
    ("iPhone18,4", "iPhone Air", "A3260"),
    ("iPhone18,5", "iPhone 17e", "A3575"),
    ("iPhone19,2", "iPhone 18 Pro", "A3472"),
    ("iPhone19,3", "iPhone 18 Pro Max", "A3473"),
    ("iPhone19,7", "iPhone 18 Pro Max", "A3473"),
    ("iPhone19,4", "iPhone Duo", "A3447")
]

// The device table and its lookup fallbacks are cache-side and need no
// kernel answer: the profile must resolve from the product type (with or
// without a board suffix) or the marketing-name fallback.
func checkNative(_ cache: [String: Any], name: String, model: String) {
    let plist = GestaltPlist(dict: ["CacheExtra": cache])
    guard let profile = AIRegionProfile(plist: plist) else {
        fatalError("Missing native profile: \(cache)")
    }
    precondition(profile.marketingName == name)
    precondition(profile.regulatoryModel == model)
}

for (identifier, name, model) in newDevices {
    // Product identity works without a marketing name, including board suffixes
    // and when a previously edited marketing name disagrees with the hardware.
    checkNative([productKey: identifier], name: name, model: model)
    checkNative([productKey: identifier + "-A"], name: name, model: model)
    checkNative([productKey: identifier, marketingKeys[0]: "iPhone 15 Pro"], name: name, model: model)
    for key in marketingKeys {
        checkNative([productKey: "Unknown", key: name], name: name, model: model)
    }
}

checkNative([productKey: "iPhone16,1"], name: "iPhone 15 Pro", model: "A2848")
checkNative([productKey: "iPhone17,5"], name: "iPhone 16e", model: "A3212")
checkNative([productKey: "iPad17,4-A"], name: "iPad Pro 13-inch (M5)", model: "A3361")
checkNative([productKey: "iPad16,9"], name: "iPad Air 11-inch (M4)", model: "A3460")

// Kernel-truth resolution: resolve() decides eligibility from hw.machine,
// never from the cache, so each scenario pins the kernel override to the
// device it simulates. A host Mac reports "arm64", which is deliberately
// never treated as eligible.
AIRegionProfile.machineIdentifierOverride = "iPhone18,1"
do {
    let plist = GestaltPlist(dict: ["CacheExtra": [productKey: "iPhone18,1"]])
    let configuration = AIRegionConfiguration.resolve(for: plist)
    precondition(configuration.profile == AIRegionProfile.profile(forProductType: "iPhone18,1"))
    precondition(!configuration.requiresDeviceSpoofing)
    precondition(configuration.spoofedProductType == nil)
    precondition(configuration.spoofedHardwareModel == nil)
    precondition(configuration.spoofedCPUModel == nil)
    precondition(configuration.enablesSiriMode)
}

AIRegionProfile.machineIdentifierOverride = "iPhone15,4"
do {
    // Unsupported-device routing: an eligible identity is borrowed only when
    // the activation mode says so; dictation-safe never spoofs identity.
    let plist = GestaltPlist(dict: ["CacheExtra": [productKey: "iPhone15,4"]])
    let safe = AIRegionConfiguration.resolve(for: plist, osMajorVersion: 27, mode: .dictationSafe)
    precondition(!safe.requiresDeviceSpoofing)
    precondition(safe.spoofedProductType == nil)
    precondition(safe.enablesSiriMode)
    let temp26 = AIRegionConfiguration.resolve(for: plist, osMajorVersion: 26, mode: .temporarySpoof)
    precondition(temp26.requiresDeviceSpoofing)
    precondition(temp26.usesTwoStageSetup == false)
    precondition(temp26.spoofedProductType == "iPhone16,1")
    let temp27 = AIRegionConfiguration.resolve(for: plist, osMajorVersion: 27, mode: .temporarySpoof)
    precondition(temp27.usesTwoStageSetup)
    precondition(temp27.enablesSiriMode)
    precondition(temp27.requiresDeviceSpoofing)
    precondition(temp27.spoofedProductType == "iPhone16,1")
    precondition(temp27.spoofedHardwareModel == "D83AP")
    precondition(temp27.spoofedCPUModel == "t8130")
    precondition(temp27.profile.regulatoryModel == "A2848")
}

AIRegionProfile.machineIdentifierOverride = "iPad15,7"
do {
    let plist = GestaltPlist(dict: ["CacheExtra": [productKey: "iPad15,7"]])
    let configuration = AIRegionConfiguration.resolve(for: plist, osMajorVersion: 27, mode: .temporarySpoof)
    precondition(configuration.usesTwoStageSetup)
    precondition(configuration.enablesSiriMode)
    precondition(configuration.requiresDeviceSpoofing)
    precondition(configuration.spoofedProductType == "iPad16,1")
    precondition(configuration.spoofedHardwareModel == "J410AP")
    precondition(configuration.spoofedCPUModel == "t8130")
    precondition(configuration.profile.regulatoryModel == "A2993")
}

AIRegionProfile.machineIdentifierOverride = nil
print("Passed: device profiles, suffix and name fallbacks, kernel-truth eligibility, dictation-safe routing and iOS 26/27 spoof setup.")
