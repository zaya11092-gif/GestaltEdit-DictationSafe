import Combine
import Foundation

@MainActor
final class GestaltViewModel: ObservableObject {
    @Published var plist: GestaltPlist?
    @Published var isDirty = false
    @Published var isBusy = false
    @Published var notice: GestaltNotice?
    @Published private(set) var hasAttemptedLoad = false
    @Published private(set) var backups: [GestaltBackup] = []
    @Published var selectedTweaks: Set<GestaltTweakID> = []
    @Published var dynamicIslandSubtype: Int?
    @Published var changesModelName = false
    @Published var modelName = ""
    @Published var stagesAIRegion = false
    @Published var regionPresetID: String?
    // Siri AI activation strategy for unsupported devices. Dictation-safe is
    // the default: it never writes device identity, so Face ID, dictation and
    // spoken Siri keep working. Temporary spoof is the fallback for setup
    // flows that refuse an unsupported device.
    @Published var aiActivationMode: SiriAIActivationMode = .dictationSafe
    // Advanced opt-in for the next Siri AI activation: additionally writes the
    // on-device Siri understanding capability flag. Off by default because it
    // drives the on-device speech pipeline and can wedge dictation.
    @Published var enablesSiriOnDevice = false
    @Published private(set) var isRespringing = false

    enum Device: Hashable { case iPhone, appleWatch }
    @Published private(set) var selectedDevice: Device = .iPhone
    @Published var isDeviceSelectorExpanded = true
    let watch = WatchConnection()
    private var watchDeviceID: String?
    private var watchSnapshot: Data?
    private var watchGeneration = 0
    private var watchSubscription: AnyCancellable?

    init() {
        watchSubscription = watch.$pairingGeneration.dropFirst().sink { [weak self] _ in
            guard let self, self.selectedDevice == .appleWatch else { return }
            self.watchGeneration += 1
            self.clearStagedChanges()
            self.isDirty = false
            self.plist = nil
            self.watchSnapshot = nil
            self.watchDeviceID = nil
            self.backups = []
        }
    }

    func selectDevice(_ device: Device) {
        guard !isBusy, device != selectedDevice else { return }
        selectedDevice = device
        plist = nil
        isDirty = false
        clearStagedChanges()
        watchSnapshot = nil
        watchDeviceID = nil
        backups = []
        load()
    }

    var deviceContextID: String {
        selectedDevice == .iPhone ? "iPhone" : "AppleWatch-\(watchGeneration)-\(watchDeviceID ?? "unavailable")"
    }

    private func clearStagedChanges() {
        selectedTweaks.removeAll()
        dynamicIslandSubtype = nil
        changesModelName = false
        modelName = ""
        stagesAIRegion = false
        regionPresetID = nil
        selectedWatchTweaks.removeAll()
        watchRegionCode = ""
        watchSalesRegion = ""
        watchResolution = -1
        watchUltraFaceClass = 29
    }

    @Published var selectedWatchTweaks: Set<String> = []
    @Published var watchRegionCode = ""
    @Published var watchSalesRegion = ""
    @Published var watchResolution = -1
    @Published var watchUltraFaceClass = 29

    var watchUltraFaceClassOptions: [Int] {
        guard selectedDevice == .appleWatch, let plist else { return [] }
        return WatchTweakCatalog.ultraFaceClasses(plist: plist, build: watch.build)
    }

    var currentWatchUltraFaceClass: Int? {
        guard selectedDevice == .appleWatch, let plist else { return nil }
        return WatchTweakCatalog.currentUltraFaceClass(plist: plist, build: watch.build)
    }

    private func syncWatchUltraFaceClass() {
        watchUltraFaceClass = currentWatchUltraFaceClass ?? watchUltraFaceClassOptions.first ?? 29
    }

    var supportsWatchFaces: Bool {
        guard selectedDevice == .appleWatch, let plist else { return false }
        return WatchTweakCatalog.faceLayout(plist: plist, build: watch.build) != nil
    }

    private let access = GestaltAccess.shared()

    var aiRegionProfile: AIRegionProfile? {
        plist.flatMap(AIRegionProfile.init(plist:))
    }

    var requiresForcedAIEnable: Bool {
        // True when the device has no eligible Siri AI product profile, so
        // activation depends on the staged capability flags. Mode-independent:
        // dictation-safe and temporary-spoof both apply to these devices.
        plist.map { AIRegionProfile(plist: $0) == nil } ?? false
    }

    var hasStagedTweaks: Bool {
        if selectedDevice == .appleWatch { return stagedChangeCount > 0 }
        return !selectedTweaks.isEmpty
            || dynamicIslandSubtype != nil
            || (changesModelName && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || stagesAIRegion
            || regionPresetID != nil
    }

    var stagedChangeCount: Int {
        if selectedDevice == .appleWatch {
            return selectedWatchTweaks.count + (watchRegionCode.isEmpty ? 0 : 1)
                + (watchSalesRegion.isEmpty ? 0 : 1) + (watchResolution >= 0 ? 1 : 0)
        }
        return selectedTweaks.count
            + (dynamicIslandSubtype == nil || selectedTweaks.contains(.supportsDynamicIsland) ? 0 : 1)
            + (changesModelName ? 1 : 0)
            + (stagesAIRegion ? 1 : 0)
            + (regionPresetID == nil ? 0 : 1)
    }

    func load() {
        guard !isBusy else { return }
        hasAttemptedLoad = true
        if selectedDevice == .appleWatch { loadWatch(); return }
        isBusy = true
        notice = nil

        defer { isBusy = false }
        do {
            try access.connect()
            guard let dictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            plist = GestaltPlist(dict: dictionary)
            isDirty = false
            refreshBackups()
        } catch {
            plist = nil
            report(error)
        }
    }

    var stagedAIRegionPresetID: String? {
        guard stagesAIRegion, let plist else { return regionPresetID }
        return AIRegionConfiguration.resolve(for: plist).changesRegion ? "LL" : regionPresetID
    }

    func setRegionPreset(_ id: String?) {
        guard !stagesAIRegion else { return }
        regionPresetID = id
    }

    func setTweak(_ id: GestaltTweakID, enabled: Bool) {
        selectedTweaks = GestaltTweakCatalog.selecting(id, enabled: enabled, in: selectedTweaks)
    }

    func setAIRegion(enabled: Bool) {
        stagesAIRegion = enabled
        if enabled {
            regionPresetID = nil
        }
        if enabled, requiresForcedAIEnable {
            notice = GestaltNotice(kind: .riskWarning, message: activationWarning)
        }
    }

    func setAIActivationMode(_ mode: SiriAIActivationMode) {
        guard mode != aiActivationMode else { return }
        aiActivationMode = mode
        if stagesAIRegion, requiresForcedAIEnable {
            notice = GestaltNotice(kind: .riskWarning, message: activationWarning)
        }
    }

    private var activationWarning: String {
        if aiActivationMode == .aiExpansion {
            let base = String(localized: "AI Expansion spoofs an eligible device identity (iPhone 15 Pro class) and keeps it in place until you revert it. This is the only mode in which Image Playground and the dedicated Siri app appear and stay installed. The trade-off is real: this is the same borrowed identity that wedged dictation before, so Face ID and dictation may stop working while it is active, and speech resources downloaded under it can wedge their languages. Revert any time with Device Doctor → Fix Detected Errors or Restore → “Remove Device Spoof”, then re-add each dictation language on Wi-Fi. A backup is saved before writing.")
            return enablesSiriOnDevice
                ? base + " " + String(localized: "On-Device Siri Understanding is also enabled: this flag drives the on-device speech pipeline and can wedge dictation or spoken Siri. Device Doctor → Fix Detected Errors removes it again if that happens.")
                : base
        }
        guard aiActivationMode == .temporarySpoof else {
            let base = String(localized: "Dictation-safe mode writes only the Siri AI capability flags (AI capability and SiriMode 2). Device identity is never modified, so Face ID, dictation and spoken Siri keep working. If Settings refuses to download the Siri AI models, switch the activation mode to “Temporary Spoof”, complete the download, then use Restore → “Remove Device Spoof” and restart. Availability still depends on Apple's servers and region.")
            return enablesSiriOnDevice
                ? base + " " + String(localized: "On-Device Siri Understanding is also enabled: this flag drives the on-device speech pipeline and can wedge dictation or spoken Siri. Device Doctor → Fix Detected Errors removes it again if that happens.")
                : base
        }
        let twoStage = plist.map { AIRegionConfiguration.resolve(for: $0, mode: .temporarySpoof).usesTwoStageSetup } ?? false
        return twoStage
            ? String(localized: "First, this will temporarily spoof an eligible device. Face ID and dictation may stop working while spoofed. Complete the Siri AI model download in Settings, then open Restore and use “After Model Download · Remove Device Spoof”. After removing the spoof and restarting, Face ID and dictation will work again while Siri AI settings stay enabled. A separate full backup is also saved before setup. System instability is possible.")
            : String(localized: "This device does not officially support Siri AI. Force enabling spoofs the product, hardware, and CPU model. It may temporarily break Face ID, cause system instability or boot loops, and could require restoring the device. A backup will be created before writing.")
    }

    private var selectedBackupActions: [String] {
        var actions: [String]
        if selectedDevice == .appleWatch {
            actions = WatchTweakCatalog.definitions.filter { selectedWatchTweaks.contains($0.id) }.map(\.title)
            if !watchRegionCode.isEmpty { actions.append(String(localized: "Region") + ": " + watchRegionCode) }
            if !watchSalesRegion.isEmpty { actions.append(String(localized: "Sales Region") + ": " + watchSalesRegion) }
            if WatchTweakCatalog.resolutions.indices.contains(watchResolution) { actions.append(String(localized: "Resolution")) }
        } else {
            actions = GestaltTweakCatalog.definitions.filter { selectedTweaks.contains($0.id) }.map(\.title)
            if dynamicIslandSubtype != nil { actions.append(String(localized: "Dynamic Island")) }
            if changesModelName { actions.append(String(localized: "Model Name")) }
            if let regionPresetID { actions.append(String(localized: "Region") + ": " + regionPresetID) }
            if stagesAIRegion {
                actions.append(String(localized: "Enable Siri AI"))
                if enablesSiriOnDevice { actions.append(String(localized: "On-Device Siri Understanding")) }
            }
        }
        return actions
    }

    func applySelectedTweaks() {
        if selectedDevice == .appleWatch { applyWatchTweaks(); return }
        guard !isBusy, var pending = plist else { return }
        do {
            for id in selectedTweaks {
                guard let definition = GestaltTweakCatalog.definition(for: id) else { continue }
                try pending.apply(definition: definition)
            }
            if let dynamicIslandSubtype {
                try pending.setDynamicIslandSubtype(dynamicIslandSubtype)
            }
            if changesModelName {
                let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw GestaltEditError.emptyModelName }
                try pending.setModelName(name)
            }
            if let regionPresetID,
               let region = GestaltRegionPreset.all.first(where: { $0.id == regionPresetID }) {
                pending.apply(region: region)
            }
            var expectedConfiguration: AIRegionConfiguration?
            if stagesAIRegion {
                let configuration = AIRegionConfiguration.resolve(
                    for: pending, mode: aiActivationMode,
                    enableSiriOnDevice: enablesSiriOnDevice)
                configuration.apply(to: &pending)
                expectedConfiguration = configuration
            }
            save(pending, expectedAIRegion: expectedConfiguration, actions: selectedBackupActions) { [weak self] in
                self?.selectedTweaks.removeAll()
                self?.dynamicIslandSubtype = nil
                self?.changesModelName = false
                self?.modelName = ""
                self?.stagesAIRegion = false
                self?.enablesSiriOnDevice = false
                self?.regionPresetID = nil
            }
        } catch {
            report(error)
        }
    }

    func applyChanges() {
        guard !isBusy, let plist else { return }
        save(plist, expectedAIRegion: nil)
    }

    func createBackup() {
        guard !isBusy else { return }
        if selectedDevice == .appleWatch { backupWatch(); return }
        isBusy = true
        defer { isBusy = false }
        do {
            try access.connect()
            let data = try access.readGestaltData()
            let backup = try GestaltBackupStore.create(from: data, record: .init(source: .manual, actions: [], changes: []))
            refreshBackups()
            notice = GestaltNotice(
                kind: .backupCreated,
                message: String(
                    format: String(localized: "Saved %@.plist. You can export it from the Backups tab."),
                    backup.name
                )
            )
        } catch {
            report(error)
        }
    }

    func importBackup(from url: URL) {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        guard selectedDevice != .appleWatch || watchDeviceID != nil else {
            report(WatchMGWire.failure(String(localized: "Reload Apple Watch before saving.")))
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            let backup = try GestaltBackupStore.create(from: data, deviceID: selectedDevice == .appleWatch ? watchDeviceID : nil, record: .init(source: .imported, actions: [], changes: []))
            refreshBackups()
            notice = GestaltNotice(
                kind: .backupCreated,
                message: String(
                    format: String(localized: "Imported %@ and saved it as %@.plist."),
                    url.lastPathComponent,
                    backup.name
                )
            )
        } catch {
            report(error)
        }
    }

    func restore(_ backup: GestaltBackup) {
        guard !isBusy else { return }
        do {
            let data = try GestaltBackupStore.data(for: backup)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            let snapshot = GestaltPlist(dict: dictionary)
            if backup.purpose == .siriAIIdentityRestore {
                guard selectedDevice == .iPhone,
                      snapshot.dict["CacheExtra"] is [String: Any],
                      let currentDictionary = try access.readGestalt() as? [String: Any] else {
                    throw GestaltEditError.invalidBackup
                }
                // The snapshot must describe the physical device. Comparing
                // against the live cache would false-reject clean snapshots
                // whenever the live cache is itself still spoofed.
                guard DictationRepairRestore.matchesPhysicalDevice(snapshot) else {
                    throw GestaltEditError.wrongDeviceBackup
                }
                let current = GestaltPlist(dict: currentDictionary)
                let restored = SiriAIIdentityRestore.restoring(current, from: snapshot)
                save(restored, expectedAIRegion: nil,
                     expectedIdentity: SiriAIIdentityRestore.values(in: snapshot),
                     source: .restore, actions: [String(localized: "Remove Device Spoof")]) { [weak self] in
                    self?.clearStagedChanges()
                }
            } else {
                save(snapshot, expectedAIRegion: nil, source: .restore, actions: [String(localized: "Restore Backup"), backup.name]) { [weak self] in self?.clearStagedChanges() }
            }
        } catch {
            report(error)
        }
    }

    func delete(_ backup: GestaltBackup) {
        do {
            try GestaltBackupStore.delete(backup)
            refreshBackups()
        } catch {
            report(error)
        }
    }

    /// Repairs dictation and Face ID damage left behind by a device spoof
    /// (from GestaltEdit, GestaltX, Gester or any other editor): restores the
    /// complete hardware identity and the device-specific on-device Siri
    /// capability from a verified original backup while keeping AI, SiriMode,
    /// region and unrelated settings.
    func repairDictation(from backup: GestaltBackup) {
        guard !isBusy else { return }
        do {
            let data = try GestaltBackupStore.data(for: backup)
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let dictionary = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            let snapshot = GestaltPlist(dict: dictionary)
            guard selectedDevice == .iPhone,
                  let currentDictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidBackup
            }
            let current = GestaltPlist(dict: currentDictionary)
            // The repair source must describe the physical device. Backups
            // taken while a spoof was active are rejected, never guessed.
            // The live cache is deliberately NOT compared against the backup:
            // when it is still spoofed the comparison would false-reject the
            // one backup that can fix it.
            guard DictationRepairRestore.matchesPhysicalDevice(snapshot) else {
                throw GestaltEditError.mismatchedIdentityBackup
            }
            let repaired = DictationRepairRestore.restoring(current, from: snapshot)
            save(repaired, expectedAIRegion: nil,
                 expectedIdentity: DictationRepairRestore.values(in: snapshot),
                 identityKeys: DictationRepairRestore.keys,
                 source: .restore,
                 actions: [String(localized: "Dictation & Face ID Repair")]) { [weak self] in
                self?.clearStagedChanges()
            }
        } catch {
            report(error)
        }
    }

    func refreshBackups() {
        do {
            if selectedDevice == .appleWatch && watchDeviceID == nil { backups = []; return }
            backups = try GestaltBackupStore.list(deviceID: selectedDevice == .appleWatch ? watchDeviceID : nil)
        } catch {
            report(error)
        }
    }

    // MARK: Device Doctor

    /// Read-only scan comparing the live MobileGestalt cache with the values
    /// the hardware itself reports (kernel, IOKit) and any verified local
    /// backup. Diagnoses leftover device spoofs that break dictation, spoken
    /// Siri and Face ID — with or without a pre-spoof backup.
    @Published var identityAudit: DeviceIdentityAudit.Report?

    func runIdentityAudit() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        do {
            guard let currentDictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            identityAudit = DeviceIdentityAudit.audit(
                GestaltPlist(dict: currentDictionary),
                kernelHardwareModel: IdentityProbe.kernelHardwareModel,
                ioKitPlatform: IdentityProbe.ioKitPlatformName,
                backupIdentity: verifiedBackupIdentity()
            )
        } catch {
            report(error)
        }
    }

    /// Identity values from a local backup that provably describes this
    /// physical device — the safest repair source when one exists.
    private func verifiedBackupIdentity() -> NSDictionary? {
        for backup in backups {
            guard let data = try? GestaltBackupStore.data(for: backup),
                  let dictionary = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else { continue }
            let candidate = GestaltPlist(dict: dictionary)
            if DictationRepairRestore.matchesPhysicalDevice(candidate) {
                return SiriAIIdentityRestore.values(DeviceIdentityAudit.identityKeys, in: candidate)
            }
        }
        return nil
    }

    func identityFixPlan(
        removeSiriOnDevice: Bool,
        removeSiriAIKeys: Bool,
        removeRegionOverrides: Bool,
        regulatoryModelOverride: String?
    ) -> DeviceIdentityAudit.FixPlan? {
        guard let report = identityAudit else { return nil }
        return DeviceIdentityAudit.fixPlan(
            from: report,
            removeSiriOnDevice: removeSiriOnDevice,
            removeSiriAIKeys: removeSiriAIKeys,
            removeRegionOverrides: removeRegionOverrides,
            regulatoryModelOverride: regulatoryModelOverride
        )
    }

    /// Factory cache reset: wipes every cached MobileGestalt answer (after an
    /// automatic backup) so iOS rebuilds a brand-new native cache on the next
    /// restart. This removes all MobileGestalt modifications — Siri AI
    /// activation, region overrides, cosmetic edits — and is the guaranteed
    /// cure when the cache itself is the problem but no single audited key
    /// explains it.
    func rebuildGestaltCache() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        do {
            guard let currentDictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            var pending = GestaltPlist(dict: currentDictionary)
            pending.clearCacheExtra()
            save(pending, expectedAIRegion: nil, expectedIdentity: nil,
                 source: .identityRecovery,
                 actions: [String(localized: "Factory Cache Reset")]) { [weak self] in
                guard let self else { return }
                self.clearStagedChanges()
                self.notice = GestaltNotice(
                    kind: .repaired,
                    message: String(localized: "MobileGestalt cache cleared. Fully restart the iPhone — iOS rebuilds a native cache on boot. All MobileGestalt modifications are removed; Siri AI can be re-enabled afterwards.")
                )
            }
        } catch {
            report(error)
        }
    }

    /// Applies a Device Doctor plan through the verified save path: the
    /// current file is backed up automatically, then re-read and compared
    /// against the expected identity before the result is trusted.
    func applyIdentityFix(_ plan: DeviceIdentityAudit.FixPlan) {
        guard !isBusy, plan.hasChanges, selectedDevice == .iPhone else { return }
        do {
            guard let currentDictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            var pending = GestaltPlist(dict: currentDictionary)
            DeviceIdentityAudit.applying(plan, to: &pending)
            let expected = SiriAIIdentityRestore.values(DeviceIdentityAudit.identityKeys, in: pending)
            save(pending, expectedAIRegion: nil,
                 expectedIdentity: expected,
                 identityKeys: DeviceIdentityAudit.identityKeys,
                 source: .identityRecovery,
                 actions: [String(localized: "Device Doctor Fix")]) { [weak self] in
                guard let self else { return }
                self.clearStagedChanges()
                self.notice = GestaltNotice(
                    kind: .repaired,
                    message: String(localized: "Device identity repaired. Restart the iPhone for dictation, spoken Siri and Face ID to recover.")
                )
            }
        } catch {
            report(error)
        }
    }

    private func siriAIOriginalIdentity(current: GestaltPlist, configuration: AIRegionConfiguration) throws -> GestaltPlist {
        // Reapplying setup must not replace the real identity baseline with an
        // already-spoofed identity. Prefer the dedicated recovery snapshot.
        guard current.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String == configuration.spoofedProductType else {
            return current
        }
        let saved = try GestaltBackupStore.list()
        let candidates = saved.filter { $0.purpose == .siriAIIdentityRestore }
            + saved.filter { $0.purpose != .siriAIIdentityRestore }.reversed()
        for backup in candidates {
            guard let data = try? GestaltBackupStore.data(for: backup),
                  let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  dictionary["CacheExtra"] is [String: Any] else { continue }
            let candidate = GestaltPlist(dict: dictionary)
            if DictationRepairRestore.matchesPhysicalDevice(candidate),
               candidate.cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String != configuration.spoofedProductType {
                return candidate
            }
        }
        throw GestaltEditError.missingOriginalIdentityBackup
    }

    private func save(
        _ pendingPlist: GestaltPlist,
        expectedAIRegion: AIRegionConfiguration?,
        expectedIdentity: NSDictionary? = nil,
        identityKeys: [String]? = nil,
        source: GestaltBackupRecord.Source = .modification,
        actions: [String] = [],
        completion: (() -> Void)? = nil
    ) {
        if selectedDevice == .appleWatch {
            saveWatch(pendingPlist, source: source, actions: actions, completion: completion)
            return
        }
        isBusy = true
        notice = nil

        do {
            let originalData = try access.readGestaltData()
            let record = try GestaltBackupRecord.modification(from: originalData, to: pendingPlist.dict, source: source, actions: actions)
            let automaticBackup = try GestaltBackupStore.create(from: originalData, record: record)
            var originalPlist: GestaltPlist?
            if expectedAIRegion != nil || expectedIdentity != nil {
                guard let originalDictionary = try PropertyListSerialization.propertyList(from: originalData, format: nil) as? [String: Any],
                      originalDictionary["CacheExtra"] is [String: Any] else {
                    throw GestaltEditError.invalidPlist
                }
                originalPlist = GestaltPlist(dict: originalDictionary)
            }
            // Every identity-bearing activation (temporary spoof and AI
            // Expansion) pre-creates a one-tap recovery backup that restores
            // the real identity and drops the iOS 27 expansion flag.
            if let configuration = expectedAIRegion, configuration.requiresDeviceSpoofing {
                guard let original = originalPlist else {
                    throw GestaltEditError.invalidPlist
                }
                let baseline = try siriAIOriginalIdentity(current: original, configuration: configuration)
                let recovery = SiriAIIdentityRestore.restoring(pendingPlist, from: baseline)
                let recoveryData = try PropertyListSerialization.data(fromPropertyList: recovery.dict, format: .binary, options: 0)
                _ = try GestaltBackupStore.create(from: recoveryData, purpose: .siriAIIdentityRestore,
                    record: try .modification(from: PropertyListSerialization.data(fromPropertyList: pendingPlist.dict, format: .binary, options: 0),
                                              to: recovery.dict, source: .identityRecovery, actions: []))
            }
            try access.saveGestalt(pendingPlist.dict)
            guard let verification = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            let verifiedPlist = GestaltPlist(dict: verification)
            if let expectedIdentity {
                let keys = identityKeys ?? SiriAIIdentityRestore.keys
                guard expectedIdentity.isEqual(SiriAIIdentityRestore.values(keys, in: verifiedPlist)) else {
                    throw GestaltEditError.verificationFailed
                }
            }

            if let expectedAIRegion {
                let cacheExtra = verifiedPlist.cacheExtra
                guard AIRegionConfiguration.regionValues(in: verifiedPlist)
                    .isEqual(AIRegionConfiguration.regionValues(in: pendingPlist)) else {
                    throw GestaltEditError.verificationFailed
                }
                if expectedAIRegion.enablesSiriMode {
                    guard cacheExtra["a3n5T9sFtlyQ74NEp9ESxg"] as? Int == 2,
                          cacheExtra["A62OafQ85EJAiiqKn4agtg"] as? Int == 1 else {
                        throw GestaltEditError.verificationFailed
                    }
                }
                if expectedAIRegion.requiresDeviceSpoofing {
                    guard cacheExtra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String == expectedAIRegion.spoofedProductType,
                          cacheExtra["oYicEKzVTz4/CxxE05pEgQ"] as? String == expectedAIRegion.spoofedHardwareModel,
                          cacheExtra["5pYKlGnYYBzGvAlIU8RjEQ"] as? String == expectedAIRegion.spoofedCPUModel else {
                        throw GestaltEditError.verificationFailed
                    }
                } else if !expectedAIRegion.rewritesRegulatoryModel {
                    // Dictation-safe writes must leave hardware identity and
                    // the on-device Siri capability exactly as they were.
                    guard let original = originalPlist,
                          SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: original)
                            .isEqual(SiriAIIdentityRestore.values(DictationRepairRestore.keys, in: verifiedPlist)) else {
                        throw GestaltEditError.verificationFailed
                    }
                }
            }

            if NSDictionary(dictionary: verification).isEqual(to: pendingPlist.dict) {
                try? GestaltBackupStore.markVerified(automaticBackup)
            }
            plist = verifiedPlist
            isDirty = false
            completion?()
            refreshBackups()
            isBusy = false
            isRespringing = true
        } catch {
            isDirty = true
            refreshBackups()
            report(error)
            isBusy = false
        }
    }

    private func applyWatchTweaks() {
        guard !isBusy, let plist else { return }
        do {
            var pending = plist
            if !watchRegionCode.isEmpty {
                guard WatchTweakCatalog.regions.contains(where: { $0.1 == watchRegionCode }) else { return }
                pending.setCacheExtra(watchRegionCode, forKey: "h63QSdBCiT/z0WU6rdQv6Q")
            }
            if !watchSalesRegion.isEmpty {
                guard WatchTweakCatalog.regions.contains(where: { $0.2 == watchSalesRegion }) else { return }
                let current = "zHeENZu+wbg7PUprwNwBWg", legacy = "yK+xavymRGZ3xWc1tb8XDg"
                let hasCurrent = pending.cacheExtra[current] != nil, hasLegacy = pending.cacheExtra[legacy] != nil
                if hasCurrent || !hasLegacy { pending.setCacheExtra(watchSalesRegion, forKey: current) }
                if hasLegacy { pending.setCacheExtra(watchSalesRegion, forKey: legacy) }
            }
            // Apply the combined AI preset after manual region selections so
            // enabling it cannot leave a newly selected unsupported MG region.
            pending = try WatchTweakCatalog.apply(selectedWatchTweaks, to: pending, build: watch.build,
                                                  regionIdentifier: watch.regionIdentifier,
                                                  ultraFaceClass: watchUltraFaceClass,
                                                  original: selectedWatchTweaks.contains("ultra") ? try originalWatchCache() : nil,
                                                  hardwareIdentifier: watch.hardwareIdentifier)
            if WatchTweakCatalog.resolutions.indices.contains(watchResolution) {
                let resolution = WatchTweakCatalog.resolutions[watchResolution]
                pending.setCacheExtra(resolution.1, forKey: "g7YQ1Djxh4YiKlEeaoGhzg")
                pending.setCacheExtra(resolution.2, forKey: "OjzOua0LkOegX7pQdgMksw")
            }
            saveWatch(pending, actions: selectedBackupActions) { [weak self] in
                self?.clearStagedChanges()
                self?.syncWatchUltraFaceClass()
            }
        } catch { report(error) }
    }

    private func originalWatchCache() throws -> GestaltPlist {
        // Automatic pre-write backups preserve the state before the first Ultra
        // edit, including across reloads and switching back from class 38.
        if let id = watchDeviceID {
            for backup in try GestaltBackupStore.list(deviceID: id).reversed() {
                guard let data = try? GestaltBackupStore.data(for: backup),
                      let dict = try? WatchMGWire.decode(data) else { continue }
                let candidate = GestaltPlist(dict: dict)
                if WatchTweakCatalog.faceLayout(plist: candidate, build: watch.build) != nil {
                    return candidate
                }
            }
        }
        guard let watchSnapshot else { throw WatchMGWire.failure(String(localized: "Reload Apple Watch before saving.")) }
        return GestaltPlist(dict: try WatchMGWire.decode(watchSnapshot))
    }

    private func loadWatch() {
        isBusy = true
        notice = nil
        let generation = watchGeneration
        Task {
            defer { isBusy = false }
            do {
                let id = try await watch.identify()
                let data = try await watch.read(deviceID: id)
                guard generation == watchGeneration else { return }
                if watchDeviceID != id { clearStagedChanges() }
                watchDeviceID = id
                watchSnapshot = data
                plist = GestaltPlist(dict: try WatchMGWire.decode(data))
                if !selectedWatchTweaks.contains("ultra") { syncWatchUltraFaceClass() }
                isDirty = false
                refreshBackups()
            } catch {
                plist = nil
                watchSnapshot = nil
                report(error)
            }
        }
    }

    private func backupWatch() {
        guard let id = watchDeviceID else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let data = try await watch.read(deviceID: id)
                _ = try GestaltBackupStore.create(from: data, deviceID: id, record: .init(source: .manual, actions: [], changes: []))
                refreshBackups()
                notice = GestaltNotice(kind: .backupCreated, message: String(localized: "Apple Watch backup saved on this iPhone."))
            } catch { report(error) }
        }
    }

    private func saveWatch(_ pending: GestaltPlist, source: GestaltBackupRecord.Source = .modification, actions: [String] = [], completion: (() -> Void)?) {
        guard let id = watchDeviceID, let snapshot = watchSnapshot else {
            report(WatchMGWire.failure(String(localized: "Reload Apple Watch before saving.")))
            return
        }
        isBusy = true
        notice = nil
        let generation = watchGeneration
        Task {
            defer { isBusy = false }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: pending.dict, format: .binary, options: 0)
                let automaticBackup = try GestaltBackupStore.create(from: snapshot, deviceID: id,
                    record: try .modification(from: snapshot, to: pending.dict, source: source, actions: actions))
                try await watch.write(data, deviceID: id, expectedHash: WatchMGWire.digest(snapshot))
                guard generation == watchGeneration else { return }
                let verified = try await watch.read(deviceID: id)
                guard generation == watchGeneration else { return }
                let dictionary = try WatchMGWire.decode(verified)
                guard NSDictionary(dictionary: dictionary).isEqual(to: pending.dict) else {
                    throw GestaltEditError.verificationFailed
                }
                try? GestaltBackupStore.markVerified(automaticBackup)
                plist = GestaltPlist(dict: dictionary)
                watchSnapshot = verified
                isDirty = false
                completion?()
                refreshBackups()
                // Restart only after both helper-side and iPhone-side readback
                // verification succeeds. Keep restart errors separate: the MG
                // write is already committed and must not be marked dirty/retried.
                do {
                    try await watch.restartInterface(deviceID: id)
                    notice = GestaltNotice(kind: .saved, message: String(localized: "Saved to Apple Watch and verified. Automatic watch interface restart requested."))
                } catch {
                    notice = GestaltNotice(kind: .saved, message: String(
                        format: String(localized: "Saved to Apple Watch and verified, but the automatic interface restart could not be confirmed. Restart Apple Watch manually if needed.\n%@"),
                        error.localizedDescription
                    ))
                }
            } catch {
                // A timeout can occur after commit. Force a fresh read before any retry.
                watchSnapshot = nil
                isDirty = true
                refreshBackups()
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        notice = GestaltNotice(kind: .error, message: error.localizedDescription)
    }
}

private enum GestaltEditError: LocalizedError {
    case invalidPlist
    case invalidBackup
    case wrongDeviceBackup
    case mismatchedIdentityBackup
    case missingOriginalIdentityBackup
    case verificationFailed
    case emptyModelName

    var errorDescription: String? {
        switch self {
        case .invalidPlist: String(localized: "The MobileGestalt plist is not a valid dictionary.")
        case .wrongDeviceBackup: String(localized: "This Siri AI identity backup belongs to a different device.")
        case .mismatchedIdentityBackup: String(localized: "This backup's device identity does not match this physical device. Repair requires a verified original backup of this device, taken before any device spoof.")
        case .missingOriginalIdentityBackup: String(localized: "This device is already spoofed, but no original identity backup was found. Restore an original MobileGestalt backup before starting Siri AI setup again.")
        case .invalidBackup: String(localized: "The backup is not a valid MobileGestalt plist.")
        case .verificationFailed: String(localized: "The MobileGestalt values after writing do not match the expected values.")
        case .emptyModelName: String(localized: "The device model name cannot be empty.")
        }
    }
}
