import Foundation

// Run from the repository root:
// xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/CacheDataUnlock.swift GestaltEdit/DeviceIdentityAudit.swift Tests/DeviceProfiles/main.swift -o /tmp/gestalt-device-tests && /tmp/gestalt-device-tests
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
// without a board suffix) or the marketing-name fallback. Resolver routing
// (kernel truth, two-stage eligibility) is covered by the GestaltPresets
// suite.
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

// Devices without an AI-eligible profile resolve to no profile at all.
for identifier in ["iPhone15,4", "iPhone99,1", "iPad15,7", "iPad99,1"] {
    let plist = GestaltPlist(dict: ["CacheExtra": [productKey: identifier]])
    precondition(AIRegionProfile(plist: plist) == nil)
}

// Hardware-truth helpers used by the two-stage unlock.
precondition(DeviceIdentityAudit.expectedBoard(for: "iPhone15,4") == "D37AP")
precondition(DeviceIdentityAudit.expectedCPU(for: "iPhone15,4") == "t8120")
precondition(DeviceIdentityAudit.expectedBoard(for: "iPhone18,1") == "V53AP")
precondition(DeviceIdentityAudit.expectedBoard(for: "iPhone99,9") == nil)

print("Passed: device profiles, suffix and name fallbacks, ineligible routing and hardware-truth helpers.")
