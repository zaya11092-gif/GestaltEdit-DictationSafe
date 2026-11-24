import Foundation

// Run from the repository root:
// xcrun swiftc GestaltEdit/ModelAssetInventory.swift Tests/ModelAssets/main.swift -o /tmp/gestalt-model-asset-tests && /tmp/gestalt-model-asset-tests

// The asset store hides its downloads two ways: the bundles live inside
// purpose_auto/ rather than at the namespace root, and every model generation
// uses the same directory names. So the Device Doctor probe has to enter that
// folder and read each bundle's own Info.plist. These cover the pure parts of
// that; the lease and the store itself need a device.

precondition(ModelAssetInventory.bundleNames(
    in: ["b.asset", "a.asset", "purpose_auto", "x.gepx", "c.asset.gestaltedit-hidden"]
) == ["a.asset", "b.asset"])

let plist: [String: Any] = [
    "AssetVersion": "27.1.1",
    "AssetType": "com.apple.MobileAsset.UAF.FM.GenerativeModels",
    "Measurement": Data(repeating: 0, count: 64),
    "AssetProperties": [
        "Build": "27A123",
        "DeviceClasses": ["iPhone"],
        "ModelVersion": "3",
        "UnrelatedNote": "must not be surfaced",
    ],
]

let flat = ModelAssetInventory.flattenedProperties(plist)
let keys = flat.map { $0.0 }
precondition(keys.contains("AssetVersion"))
precondition(keys.contains("AssetProperties.Build"))
precondition(keys.contains("AssetProperties.DeviceClasses"))
precondition(!keys.contains("AssetProperties.UnrelatedNote"))
precondition(flat.first { $0.0 == "Measurement" }?.1 == "<64 bytes>")
precondition(flat.first { $0.0 == "AssetProperties.DeviceClasses" }?.1 == "[iPhone]")

// Nested keys are filtered to the descriptive ones; top-level entries are
// always reported so an unfamiliar schema still yields data.
precondition(ModelAssetInventory.isDescriptive("MinimumCompatibilityVersion"))
precondition(ModelAssetInventory.isDescriptive("DeviceClasses"))
precondition(!ModelAssetInventory.isDescriptive("UnrelatedNote"))

// Size is the cheapest decisive datum: a stub cannot be a model.
precondition(ModelAssetInventory.sizeVerdict(3_000_000_000).contains("weights"))
precondition(ModelAssetInventory.sizeVerdict(300_000_000).contains("too small"))
precondition(ModelAssetInventory.sizeVerdict(30_000_000).contains("manifest"))

let bundle = ModelAssetInventory.AssetBundle(
    name: "com.apple.MobileAsset.UAF.FM.GenerativeModels.asset",
    infoPath: "purpose_auto/com.apple.MobileAsset.UAF.FM.GenerativeModels.asset/Info.plist",
    directoryPath: "/private/var/MobileAsset/AssetsV2/x.asset",
    properties: flat,
    sizeInBytes: 3_000_000_000,
    sizeWasTruncated: false)
let line = ModelAssetInventory.summary(for: bundle)
precondition(line.contains("weights"))
precondition(line.contains("27.1.1"))
precondition(line.contains("27A123"))

// Bundle measurement: recursive, regular files only, and bounded — the cap
// must report a lower bound rather than a wrong total.
let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("gestalt-model-asset-\(UUID().uuidString)")
let assets = root.appendingPathComponent("x.asset")
try! FileManager.default.createDirectory(
    at: assets.appendingPathComponent("a/b"), withIntermediateDirectories: true)
try! Data(repeating: 7, count: 1000).write(to: assets.appendingPathComponent("a/blob.bin"))
try! Data(repeating: 7, count: 24).write(to: assets.appendingPathComponent("a/b/small.bin"))

let measured = ModelAssetInventory.measureBundle(at: assets.path)
precondition(measured.size == 1024)
precondition(measured.truncated == false)
precondition(ModelAssetInventory.measureBundle(at: assets.path, entryLimit: 1).truncated)
precondition(ModelAssetInventory.measureBundle(
    at: root.appendingPathComponent("missing.asset").path).size == nil)

try? FileManager.default.removeItem(at: root)

precondition(!ModelAssetInventory.formattedSize(0).isEmpty)

// The layout the probe actually has to walk, reproduced on disk: bundles one
// level down inside purpose_auto/, each with its own Info.plist. A simulator
// cannot exercise this, because no simulator carries an Apple Intelligence
// asset store — so the fixture is the only real cover for the path.
let store = FileManager.default.temporaryDirectory
    .appendingPathComponent("gestalt-store-\(UUID().uuidString)")
let namespace = store.appendingPathComponent("com_apple_MobileAsset_UAF_FM_GenerativeModels")
let bundleDir = namespace
    .appendingPathComponent("purpose_auto/com.apple.MobileAsset.UAF.FM.GenerativeModels.asset")
try! FileManager.default.createDirectory(
    at: bundleDir.appendingPathComponent("weights"), withIntermediateDirectories: true)
try! Data(repeating: 3, count: 2048).write(to: bundleDir.appendingPathComponent("weights/model.bin"))

let assetPlist: [String: Any] = [
    "AssetVersion": "27.0.3",
    "AssetProperties": ["Build": "27A200", "ModelVersion": "4", "DeviceClasses": ["iPhone"]],
]
let assetData = try! PropertyListSerialization.data(
    fromPropertyList: assetPlist, format: .binary, options: 0)
try! assetData.write(to: bundleDir.appendingPathComponent("Info.plist"))

// purpose_auto/ — the layout the asset system actually uses.
let listing = try! FileManager.default.contentsOfDirectory(
    atPath: namespace.appendingPathComponent("purpose_auto").path)
let found = ModelAssetInventory.bundles(
    in: listing, under: "purpose_auto", rootDirectory: namespace.path)
precondition(found.count == 1)
let foundBundle = found[0]
precondition(foundBundle.name == "com.apple.MobileAsset.UAF.FM.GenerativeModels.asset")
precondition(foundBundle.infoPath
    == "purpose_auto/com.apple.MobileAsset.UAF.FM.GenerativeModels.asset/Info.plist")
precondition(foundBundle.sizeInBytes == 2048 + Int64(assetData.count))
precondition(foundBundle.properties.contains { $0.0 == "AssetVersion" && $0.1 == "27.0.3" })
precondition(foundBundle.properties.contains { $0.0 == "AssetProperties.ModelVersion" && $0.1 == "4" })
precondition(ModelAssetInventory.summary(for: foundBundle).contains("27.0.3"))
precondition(ModelAssetInventory.summary(for: foundBundle).contains("27A200"))

// Root-level layout — where the probe falls back when bundles are not nested,
// and where a bundle with no Info.plist must still be measured, not skipped.
let flatNamespace = store
    .appendingPathComponent("com_apple_MobileAsset_UAF_FM_GenerativeModels_SiriSummarization")
try! FileManager.default.createDirectory(
    at: flatNamespace.appendingPathComponent("x.asset"), withIntermediateDirectories: true)
try! Data(repeating: 1, count: 512).write(to: flatNamespace.appendingPathComponent("x.asset/blob.bin"))
let rootListing = try! FileManager.default.contentsOfDirectory(atPath: flatNamespace.path)
let rootFound = ModelAssetInventory.bundles(
    in: rootListing, under: nil, rootDirectory: flatNamespace.path)
precondition(rootFound.count == 1)
precondition(rootFound[0].infoPath == "x.asset/Info.plist")
precondition(rootFound[0].sizeInBytes == 512)
precondition(rootFound[0].properties.isEmpty)

// A missing store must read as empty rather than as an error, since the probe
// reports reachability separately from contents.
precondition(ModelAssetInventory.bundles(
    in: ["purpose_auto", "x.gepx"], under: "purpose_auto",
    rootDirectory: store.appendingPathComponent("absent").path).isEmpty)

try? FileManager.default.removeItem(at: store)

print("Passed: asset bundle discovery, plist flattening, size verdicts, bundle measurement, purpose_auto and root-layout walks.")
