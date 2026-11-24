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
    @Published var regionPresetID: String?
    // Two-stage Siri AI unlock (YumEdit method). Stage 1 writes the US sales
    // region, SiriMode 2, the generative capability flag and opens the
    // CacheData eligibility gate, with an optional ProductType-only borrow;
    // stage 2 restores the real identity from a trusted backup once the
    // resources are downloaded.
    @Published var stagesSiriAI = false
    @Published var siriAIStageMode: SiriAIYumUnlock.StageMode = .classic
    @Published var yumBorrowEnabled = false
    @Published var yumBorrowProduct = "iPhone18,5"
    // Experimental AI capability keys (see ExperimentalAICapabilities): the
    // set is the TARGET state, synced from the cache on load and mutated by
    // the research toggles; Apply reconciles cache to set through the
    // verified save path.
    @Published var experimentalAIKeys: Set<String> = []
    // Staged CacheData boolean-cell flips (offset → new value) from the
    // research scanner.
    @Published var cacheDataBitChanges: [Int: UInt8] = [:]

    func experimentalKeyOn(_ key: String) -> Bool {
        experimentalAIKeys.contains(key)
    }

    func setExperimentalKey(_ key: String, on: Bool) {
        if on {
            experimentalAIKeys.insert(key)
        } else {
            experimentalAIKeys.remove(key)
        }
    }

    private var hasExperimentalAIKeyChanges: Bool {
        guard let cache = plist?.cacheExtra else { return false }
        return ExperimentalAICapabilities.hasChanges(cache: cache, selected: experimentalAIKeys)
    }

    private func syncExperimentalSelection() {
        guard let cache = plist?.cacheExtra else { return }
        experimentalAIKeys = ExperimentalAICapabilities.selectedKeys(in: cache)
    }

    /// CacheData cells overlaid with staged bit flips.
    var cacheDataActiveCells: [CacheDataScanner.Cell] {
        guard let data = plist?.dict[SiriAIYumUnlock.cacheDataKey] as? Data else { return [] }
        var cells = CacheDataScanner.activeCells(data)
        for (offset, value) in cacheDataBitChanges where value == 1 {
            if !cells.contains(where: { $0.offset == offset }) {
                cells.append(CacheDataScanner.Cell(offset: offset, value: 1))
            }
        }
        return cells.sorted { $0.offset < $1.offset }
    }

    var cacheDataSuggestedCells: [CacheDataScanner.Cell] {
        guard let data = plist?.dict[SiriAIYumUnlock.cacheDataKey] as? Data else { return [] }
        return CacheDataScanner.suggestedCandidates(data)
    }

    func stageCacheDataBit(offset: Int, value: UInt8) {
        guard let data = plist?.dict[SiriAIYumUnlock.cacheDataKey] as? Data,
              (try? CacheDataUnlock.setBit(data, offset: offset, value: value)) != nil else {
            notice = GestaltNotice(
                kind: .error,
                message: String(localized: "That offset is not a valid boolean cell in the current CacheData blob — nothing was staged.")
            )
            return
        }
        cacheDataBitChanges[offset] = value
    }

    func cacheDataCellLabel(_ offset: Int) -> String? {
        CacheDataScanner.knownLabels[offset]
    }
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
        stagesSiriAI = false
        yumBorrowEnabled = false
        regionPresetID = nil
        cacheDataBitChanges = [:]
        experimentalAIKeys = []
        syncExperimentalSelection()
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
        // True when the KERNEL product type has no eligible Siri AI profile.
        // The cache is deliberately not consulted here: a ThinningProductType
        // left by another editor must never hide the activation controls from
        // a device the kernel says is ineligible.
        AIRegionProfile.profile(forProductType: AIRegionProfile.machineIdentifier) == nil
    }

    var hasStagedTweaks: Bool {
        if selectedDevice == .appleWatch { return stagedChangeCount > 0 }
        return !selectedTweaks.isEmpty
            || dynamicIslandSubtype != nil
            || (changesModelName && !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || stagesSiriAI
            || hasExperimentalAIKeyChanges
            || !cacheDataBitChanges.isEmpty
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
            + (stagesSiriAI ? 1 : 0)
            + (hasExperimentalAIKeyChanges ? 1 : 0)
            + (cacheDataBitChanges.isEmpty ? 0 : 1)
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
            syncExperimentalSelection()
            refreshBackups()
        } catch {
            plist = nil
            report(error)
        }
    }

    func setRegionPreset(_ id: String?) {
        regionPresetID = id
    }

    func setTweak(_ id: GestaltTweakID, enabled: Bool) {
        selectedTweaks = GestaltTweakCatalog.selecting(id, enabled: enabled, in: selectedTweaks)
    }

    // MARK: Siri AI two-stage unlock (YumEdit method)

    var yumState: SiriAIYumUnlock.State? {
        plist.flatMap { SiriAIYumUnlock.state(of: $0) }
    }

    /// Why Stage 1 would refuse to write right now, with the observed values,
    /// so the Siri AI section can say what to fix instead of failing on Apply.
    var siriAIStageBlockers: [String] {
        guard selectedDevice == .iPhone, let plist else { return [] }
        let machine = AIRegionProfile.machineIdentifier
        return SiriAIYumUnlock.blockingReasons(
            plist: plist,
            machine: machine,
            expectedBoard: DeviceIdentityAudit.expectedBoard(for: machine),
            expectedCPU: DeviceIdentityAudit.expectedCPU(for: machine),
            borrowProduct: siriAIStageMode == .expanded && yumBorrowEnabled ? yumBorrowProduct : nil)
    }

    private func cachedBackupPlists() throws -> [GestaltPlist] {
        try GestaltBackupStore.list().compactMap { backup -> GestaltPlist? in
            guard let data = try? GestaltBackupStore.data(for: backup),
                  let backupDictionary = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any],
                  backupDictionary["CacheExtra"] is [String: Any] else { return nil }
            return GestaltPlist(dict: backupDictionary)
        }
    }

    /// Stage 1 is staged through the global Apply button, mirroring the
    /// original app's "Enable Siri AI" + "Activation Mode" flow.
    func setStagesSiriAI(enabled: Bool) {
        stagesSiriAI = enabled
        if enabled, requiresForcedAIEnable {
            notice = GestaltNotice(
                kind: .riskWarning,
                message: String(localized: "Enable Siri AI writes AI capability flags and opens the CacheData eligibility gate. In Expanded mode, the optional Borrow switch temporarily changes ProductType only; if enabled, this can affect Face ID and dictation until Finish. On iPhone 15-class devices the new Siri did not engage on iOS 27.2.1, and dictation may wedge until the AI keys are removed again. Tap Apply to write — a backup is saved automatically.")
            )
        }
    }

    /// Stage 2: restore the real identity from the trusted same-CacheUUID
    /// backup, keeping every capability write and the open CacheData gate.
    func finishYumStageTwo() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        do {
            try access.connect()
            guard let dictionary = try access.readGestalt() as? [String: Any] else {
                throw GestaltEditError.invalidPlist
            }
            let current = GestaltPlist(dict: dictionary)
            let machine = AIRegionProfile.machineIdentifier
            guard let source = SiriAIYumUnlock.trustedIdentitySource(
                current: current,
                machine: machine,
                expectedBoard: DeviceIdentityAudit.expectedBoard(for: machine),
                expectedCPU: DeviceIdentityAudit.expectedCPU(for: machine),
                backups: try cachedBackupPlists()) else {
                throw SiriAIUnlockError.noTrustedBackup
            }
            let restored = try SiriAIYumUnlock.stageTwo(current: current, identitySource: source)
            save(restored,
                 expectedIdentity: SiriAIIdentityRestore.values(DeviceIdentityAudit.identityKeys, in: source),
                 identityKeys: DeviceIdentityAudit.identityKeys,
                 expectedYum: YumExpectation(verifyCapabilities: true, borrowedProduct: nil, requireIdentityUnchanged: false, requireGenerativeFlag: true),
                 source: .restore,
                 actions: ["Siri AI Stage 2 · Restore Real Identity"]) {
                    self.notice = GestaltNotice(
                        kind: .repaired,
                        message: String(localized: "Stage 2 complete: the real identity is restored and verified, and every capability write plus the open CacheData gate stayed in place. Fully restart the iPhone. After the restart, NEVER open Settings → Siri (or Apple Intelligence & Siri) — that page re-runs eligibility and can invalidate the downloaded resources. Test Siri by voice only, and check Face ID and dictation. If a dictation language is wedged, remove it from Dictation Languages, restart, and re-add it on Wi-Fi.")
                    )
                }
        } catch {
            report(error)
        }
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
            if stagesSiriAI {
                actions.append(String(localized: "Enable Siri AI")
                    + (siriAIStageMode == .expanded && yumBorrowEnabled ? " · " + String(localized: "Borrow") : ""))
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
            let experimentalKeyChanges = ExperimentalAICapabilities.hasChanges(
                cache: pending.cacheExtra, selected: experimentalAIKeys)
            let stagedSiriAI = stagesSiriAI
            let stagedExpanded = siriAIStageMode == .expanded
            let stagedBorrow = stagedSiriAI && stagedExpanded && yumBorrowEnabled
            if stagedSiriAI && stagedExpanded {
                let machine = AIRegionProfile.machineIdentifier
                pending = try SiriAIYumUnlock.stageOne(
                    plist: pending,
                    machine: machine,
                    expectedBoard: DeviceIdentityAudit.expectedBoard(for: machine),
                    expectedCPU: DeviceIdentityAudit.expectedCPU(for: machine),
                    borrowProduct: stagedBorrow ? yumBorrowProduct : nil)
            } else if stagedSiriAI {
                // Classic iOS 18–26 enabler: one capability key, nothing else.
                pending = SiriAIYumUnlock.classicEnable(plist: pending)
            }
            // Reconcile only when the requested experimental-key state differs.
            // This also makes an all-off selection a real, verifiable removal.
            if experimentalKeyChanges {
                var cache = pending.cacheExtra
                ExperimentalAICapabilities.reconcile(cache: &cache, selected: experimentalAIKeys)
                pending.cacheExtra = cache
            }
            // CacheData bit flips from the research scanner.
            if !cacheDataBitChanges.isEmpty {
                guard var data = pending.dict[SiriAIYumUnlock.cacheDataKey] as? Data else {
                    throw SiriAIUnlockError.cacheDataMissing
                }
                for (offset, value) in cacheDataBitChanges {
                    data = try CacheDataUnlock.setBit(data, offset: offset, value: value)
                }
                pending.setValue(data, forKey: SiriAIYumUnlock.cacheDataKey)
            }
            let experimentalExpected: NSDictionary? = experimentalKeyChanges
                ? ExperimentalAICapabilities.expectedValues(for: experimentalAIKeys)
                : nil
            let experimentalKeysList = experimentalKeyChanges
                ? ExperimentalAICapabilities.allKeys
                : nil
            let identityExclusions = (experimentalKeyChanges ? ExperimentalAICapabilities.allKeys : [])
                + (stagedBorrow ? [DictationRepairRestore.productType] : [])
            let expectedCacheData: Data? = cacheDataBitChanges.isEmpty
                ? nil
                : (pending.dict[SiriAIYumUnlock.cacheDataKey] as? Data)
            save(pending,
                 expectedIdentity: experimentalExpected,
                 identityKeys: experimentalKeysList,
                 expectedYum: stagedSiriAI
                    ? YumExpectation(verifyCapabilities: stagedExpanded,
                                     borrowedProduct: stagedBorrow ? yumBorrowProduct : nil,
                                     requireIdentityUnchanged: true,
                                     requireGenerativeFlag: true,
                                     expectedCacheData: expectedCacheData,
                                     excludeIdentityKeys: identityExclusions)
                    : (expectedCacheData != nil
                        ? YumExpectation(verifyCapabilities: false,
                                         borrowedProduct: nil,
                                         requireIdentityUnchanged: false,
                                         expectedCacheData: expectedCacheData)
                        : nil),
                 actions: selectedBackupActions) { [weak self] in
                self?.selectedTweaks.removeAll()
                self?.dynamicIslandSubtype = nil
                self?.changesModelName = false
                self?.modelName = ""
                self?.stagesSiriAI = false
                self?.yumBorrowEnabled = false
                self?.regionPresetID = nil
                self?.cacheDataBitChanges = [:]
                self?.syncExperimentalSelection()
                if stagedSiriAI {
                    self?.notice = GestaltNotice(
                        kind: .saved,
                        message: String(localized: "Stage 1 written and verified. Fully restart the iPhone now, set Siri language to match the iPhone language (a supported Apple Intelligence language), and let the Apple resources download over Wi-Fi without interruptions. Only when the download has finished, come back and run Finish · Restore Real Identity. Do not run any other fixes meanwhile.")
                    )
                }
            }
        } catch {
            report(error)
        }
    }

    func applyChanges() {
        guard !isBusy, let plist else { return }
        save(plist)
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
                save(restored, 
                     expectedIdentity: SiriAIIdentityRestore.values(in: snapshot),
                     source: .restore, actions: [String(localized: "Restore Identity · Keep AI Keys")]) { [weak self] in
                    self?.clearStagedChanges()
                }
            } else {
                save(snapshot, source: .restore, actions: [String(localized: "Restore Backup"), backup.name]) { [weak self] in self?.clearStagedChanges() }
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
            save(repaired, 
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

    // MARK: AI Feature Eligibility (GreyMatter + region template)

    /// OS Eligibility override writer. Two targets:
    /// - the systemgroup.com.apple.oseligibilityservice container — a REAL
    ///   systemgroup container, i.e. the exact path class the worse_query
    ///   lease provably works on (the MobileGestalt target is one; /var/db
    ///   paths are rejected by containermanagerd with code -6);
    /// - /var/db/eligibilityd — the classic AI eligibility store, kept as a
    ///   fallback probe.
    /// The written plist merges Nugget's 35-domain US-region eligibility
    /// template with the Apple Intelligence domains (GREYMATTER: every
    /// evaluated input — including the generative-model-system input A16
    /// devices fail — marked definitely-satisfied via override source;
    /// CALCIUM: eligible). Structure credits: Nugget (sneakyf1shy).
    private lazy var eligibilityTargets: [EligibilityAccess] = [
        EligibilityAccess(
            worseQueryTarget: "/var/containers/Shared/SystemGroup/systemgroup.com.apple.oseligibilityservice",
            plistDirectory: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.oseligibilityservice",
            fileName: "eligibility.plist",
            displayName: "OS Eligibility container"),
        EligibilityAccess(
            worseQueryTarget: "/var/db/eligibilityd",
            plistDirectory: "/private/var/db/eligibilityd",
            fileName: "eligibility.plist",
            displayName: "/var/db/eligibilityd"),
    ]

    /// One-time reachability probe per target, with a directory listing so
    /// the uncharted container contents are visible in the UI.
    @Published private(set) var eligibilityProbed = false
    @Published private(set) var eligibilityTargetReports: [String] = []
    @Published private(set) var eligibilityReachableCount = 0

    var eligibilityTargetCount: Int { eligibilityTargets.count }

    @discardableResult
    private func scanAIEligibilityTargets() -> [EligibilityAccess] {
        var reports: [String] = []
        var reachableTargets: [EligibilityAccess] = []
        for target in eligibilityTargets {
            do {
                try target.connect()
                let files = (try? target.listFiles()) ?? []
                reachableTargets.append(target)
                let fileSummary = files.isEmpty
                    ? " (empty)"
                    : ": " + files.joined(separator: ", ")
                reports.append("✓ \(target.displayName) — reachable, \(files.count) file(s)\(fileSummary)")
            } catch {
                reports.append("✗ \(target.displayName) — \(error.localizedDescription)")
            }
        }
        eligibilityProbed = true
        eligibilityReachableCount = reachableTargets.count
        eligibilityTargetReports = reports
        return reachableTargets
    }

    func probeAIEligibility() {
        guard !eligibilityProbed, selectedDevice == .iPhone else { return }
        _ = scanAIEligibilityTargets()
    }

    /// The merged override plist: Nugget's 35-domain US-region eligibility
    /// template with the Apple Intelligence domains overlaid (GREYMATTER:
    /// every evaluated input — including the generative-model-system input
    /// A16 devices fail — marked definitely-satisfied via override source;
    /// CALCIUM: eligible). When a target already carries a structured
    /// eligibility plist, its other domains are preserved and only our
    /// domains are overlaid.
    private func fullEligibilityOverride(languageCodes: [String], mergingInto existing: [String: Any]?) -> [String: Any] {
        var base: [String: Any] = [:]
        if let existing {
            base = existing
        } else if let data = EligibilityTemplate.decodedData,
                  let template = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any] {
            base = template
        }
        return AIEligibilityOverride.merged(into: base, languageCodes: languageCodes)
    }

    func applyAIEligibilityOverride(languageText: String) {
        guard !isBusy, selectedDevice == .iPhone else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            let reachableTargets = scanAIEligibilityTargets()
            guard reachableTargets.count == eligibilityTargets.count else {
                let unavailable = eligibilityTargetReports
                    .filter { $0.hasPrefix("✗") }
                    .joined(separator: "\n")
                throw GestaltEditError.eligibilityTargetsUnavailable(unavailable)
            }
            let languageCodes = languageText
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map(String.init)
                .filter { !$0.isEmpty }
            let prepared: [(target: EligibilityAccess, originalData: Data?, original: [String: Any]?, pending: [String: Any])] = try reachableTargets.map { target in
                let originalData: Data? = target.plistFileExists() ? try target.readData() : nil
                var original: [String: Any]?
                if let originalData {
                    guard let parsed = try? PropertyListSerialization.propertyList(
                        from: originalData, format: nil) as? [String: Any] else {
                        throw GestaltEditError.eligibilityInvalidPlist
                    }
                    original = parsed
                }
                return (
                    target: target,
                    originalData: originalData,
                    original: original,
                    pending: fullEligibilityOverride(languageCodes: languageCodes, mergingInto: original)
                )
            }
            for state in prepared {
                try EligibilityBackupStore.save(original: state.originalData, for: state.target.displayName)
            }

            var attempted: [Int] = []
            do {
                for (index, state) in prepared.enumerated() {
                    // Add before saving: the write may reach disk even if its
                    // post-write verification reports an error.
                    attempted.append(index)
                    try state.target.savePlist(state.pending)
                    let verification = (try? state.target.readPlist()) as? [String: Any]
                    guard let verification, AIEligibilityOverride.isApplied(verification) else {
                        throw GestaltEditError.eligibilityVerificationFailed
                    }
                }
            } catch {
                let writeError = error
                var rollbackFailures: [String] = []
                for index in attempted.reversed() {
                    let state = prepared[index]
                    do {
                        if let original = state.original {
                            try state.target.savePlist(original)
                        } else {
                            try state.target.removePlist()
                        }
                    } catch {
                        rollbackFailures.append("\(state.target.displayName): \(error.localizedDescription)")
                    }
                }
                if !rollbackFailures.isEmpty {
                    throw GestaltEditError.eligibilityRollbackFailed(
                        rollbackFailures.joined(separator: "\n") + "\nOriginal write error: " + writeError.localizedDescription)
                }
                throw writeError
            }
            notice = GestaltNotice(
                kind: .saved,
                message: String(localized: "AI feature eligibility override written and verified on every configured target. Fully restart the iPhone, then test the relevant features. Restore Original Eligibility reverts every target — the pre-apply state is backed up automatically.")
            )
        } catch {
            report(error)
        }
    }

    func revertAIEligibilityOverride() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            var restorations = 0
            for target in eligibilityTargets {
                guard EligibilityBackupStore.hasBackup(for: target.displayName) else { continue }
                let wasAbsent = EligibilityBackupStore.wasAbsent(for: target.displayName)
                let originalData = try EligibilityBackupStore.load(for: target.displayName)
                if wasAbsent {
                    try target.removePlist()
                } else if let data = originalData,
                          let original = try? PropertyListSerialization.propertyList(
                            from: data, format: nil) as? [String: Any] {
                    try target.savePlist(original)
                } else {
                    throw GestaltEditError.eligibilityNoBackup
                }
                EligibilityBackupStore.clear(for: target.displayName)
                restorations += 1
            }
            guard restorations > 0 else {
                throw GestaltEditError.eligibilityNoBackup
            }
            notice = GestaltNotice(
                kind: .repaired,
                message: String(localized: "Original eligibility state restored. Fully restart the iPhone for eligibilityd to pick it up.")
            )
        } catch {
            report(error)
        }
    }

    // MARK: Downloaded Siri AI model assets (Device Doctor)

    /// The known on-device Siri AI model asset stores. The primary path is
    /// the MobileAsset namespace the Apple Intelligence model downloads
    /// into; /var/MobileAsset is a plain system path, so the lease may be
    /// refused by containermanagerd on some builds (reported cleanly per
    /// target — the probe doubles as discovery).
    ///
    /// `bundlesSubdirectory` is the field that matters to the report: the
    /// asset system parks downloaded bundles inside `purpose_auto/`, so a
    /// listing of the namespace root reports "no .asset bundles" while the
    /// model is fully present one level down. `rootDirectory` is the absolute
    /// path, needed to measure a bundle and read its Info.plist once the
    /// lease is held.
    private lazy var modelAssetTargets: [ModelAssetTarget] = [
        ModelAssetTarget(
            id: "Generative models",
            access: EligibilityAccess(
                worseQueryTarget: "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels",
                plistDirectory: "/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels",
                fileName: "Info.plist",
                displayName: "com_apple_MobileAsset_UAF_FM_GenerativeModels"),
            rootDirectory: "/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels",
            bundlesSubdirectory: "purpose_auto"),
        ModelAssetTarget(
            id: "Siri summarization models",
            access: EligibilityAccess(
                worseQueryTarget: "/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels_SiriSummarization",
                plistDirectory: "/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels_SiriSummarization",
                fileName: "Info.plist",
                displayName: "..._GenerativeModels_SiriSummarization"),
            rootDirectory: "/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels_SiriSummarization",
            bundlesSubdirectory: "purpose_auto"),
        ModelAssetTarget(
            id: "Auto assets container",
            access: EligibilityAccess(
                worseQueryTarget: "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobileasset.autoassets",
                plistDirectory: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobileasset.autoassets",
                fileName: "Info.plist",
                displayName: "systemgroup.com.apple.mobileasset.autoassets"),
            rootDirectory: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobileasset.autoassets",
            bundlesSubdirectory: nil),
        // Namespace discovery, read-only: lists every FM / Generative /
        // GreyMatter namespace this build actually has on disk. If iOS 27
        // serves the new Siri model from a namespace of its own, it shows up
        // here and nowhere in the three known paths above.
        ModelAssetTarget(
            id: "Asset namespaces",
            access: EligibilityAccess(
                worseQueryTarget: "/var/MobileAsset/AssetsV2",
                plistDirectory: "/private/var/MobileAsset/AssetsV2",
                fileName: "Info.plist",
                displayName: "AssetsV2"),
            rootDirectory: "/private/var/MobileAsset/AssetsV2",
            bundlesSubdirectory: nil,
            discoveryFragments: ["uaf", "generative", "greymatter", "intelligen", "siri"]),
    ]

    struct ModelAssetTarget: Identifiable {
        let id: String
        let access: EligibilityAccess
        let rootDirectory: String
        /// Relative folder holding the `.asset` bundles, or nil at the root.
        let bundlesSubdirectory: String?
        /// When set, this target only reports matching directory names and
        /// is never renamed by the hide/restore actions.
        var discoveryFragments: [String] = []

        var isDiscoveryOnly: Bool { !discoveryFragments.isEmpty }
    }

    /// Renaming an asset directory with this suffix hides it from the asset
    /// system (Settings then offers a fresh download) while keeping the bytes
    /// on disk — renaming back restores the previous download without
    /// redownloading.
    static let modelAssetDisabledSuffix = ".gestaltedit-hidden"

    @Published private(set) var modelAssetsProbed = false
    @Published private(set) var modelAssetReports: [String] = []
    @Published private(set) var modelAssetHiddenCount = 0

    /// Reports what each model store actually CONTAINS, not only whether the
    /// lease reaches it. v3.2.x answered "reachable, 0 asset bundles" after a
    /// download that had completed, because the bundles sit in `purpose_auto/`.
    /// The probe now enters that folder, falls back to the root layout when
    /// the bundles are there instead, measures every bundle on disk and reads
    /// the bundle's own Info.plist — which is what says whether the downloaded
    /// model is an iOS 18–26 one or an iOS 27 one.
    func probeModelAssets() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        var reports: [String] = []
        var hidden = 0

        for target in modelAssetTargets {
            do {
                try target.access.connect()

                if target.isDiscoveryOnly {
                    let names = (try? target.access.listFiles()) ?? []
                    let matches = names.filter { name in
                        let lower = name.lowercased()
                        return target.discoveryFragments.contains { lower.contains($0) }
                    }
                    reports.append(matches.isEmpty
                        ? "✓ \(target.id) — reachable, no matching namespace"
                        : "✓ \(target.id) — \(matches.count) match(es):\n    "
                            + matches.prefix(6).joined(separator: "\n    "))
                    continue
                }

                let root = (try? target.access.listFiles()) ?? []
                hidden += root.filter { $0.hasSuffix(Self.modelAssetDisabledSuffix) }.count

                var bundles = ModelAssetInventory.bundles(
                    in: root, under: nil, rootDirectory: target.rootDirectory)
                var layout = "root"
                if let subdirectory = target.bundlesSubdirectory {
                    let listing = (try? target.access.listFiles(inSubdirectory: subdirectory)) ?? []
                    let nested = ModelAssetInventory.bundles(
                        in: listing, under: subdirectory, rootDirectory: target.rootDirectory)
                    if !nested.isEmpty {
                        bundles = nested
                        layout = subdirectory
                    }
                }
                reports.append(bundleReport(bundles: bundles, layout: layout, of: target))
            } catch {
                reports.append("✗ \(target.id) — \(error.localizedDescription)")
            }
        }

        modelAssetHiddenCount = hidden
        modelAssetReports = reports
        modelAssetsProbed = true
    }

    private func bundleReport(
        bundles: [ModelAssetInventory.AssetBundle],
        layout: String,
        of target: ModelAssetTarget
    ) -> String {
        guard !bundles.isEmpty else {
            return "✓ \(target.id) — reachable, no .asset bundle found"
        }
        var lines = ["✓ \(target.id) — \(bundles.count) bundle(s) in \(layout)"]
        for bundle in bundles.prefix(4) {
            lines.append("  \(bundle.name)")
            lines.append("    \(ModelAssetInventory.summary(for: bundle))")
            if !bundle.properties.isEmpty {
                lines.append("    " + bundle.properties
                    .prefix(6)
                    .map { "\($0.0)=\($0.1)" }
                    .joined(separator: " · "))
            }
        }
        if bundles.count > 4 { lines.append("  +\(bundles.count - 4) more") }
        return lines.joined(separator: "\n")
    }

    /// Hides every downloaded model asset bundle so Settings offers a fresh
    /// download. Reversible: "Restore Hidden Models" renames them back.
    func hideDownloadedModelAssets() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            probeModelAssets()
            var hidden = 0
            for target in modelAssetTargets where !target.isDiscoveryOnly {
                guard let files = try? target.access.listFiles() else { continue }
                for name in files where name.hasSuffix(".asset") {
                    let newName = name + GestaltViewModel.modelAssetDisabledSuffix
                    do {
                        try target.access.renameEntry(name, toName: newName)
                        hidden += 1
                    } catch {
                        modelAssetReports.append("⚠︎ \(target.id): could not hide \(name) — \(error.localizedDescription)")
                    }
                }
            }
            modelAssetHiddenCount += hidden
            notice = GestaltNotice(
                kind: .repaired,
                message: String(localized: "Hidden \(hidden) model asset bundle(s). Fully restart the iPhone, then open Settings → Apple Intelligence & Siri — it will offer a fresh model download (Enable Siri AI in Classic mode and matching Siri/iPhone language first, if the page does not). Restore Hidden Models brings the previous download back without redownloading.")
            )
        } catch {
            report(error)
        }
    }

    /// Renames previously hidden model asset bundles back to their original
    /// names, restoring the previous download without a redownload.
    func restoreHiddenModelAssets() {
        guard !isBusy, selectedDevice == .iPhone else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            probeModelAssets()
            var restored = 0
            for target in modelAssetTargets where !target.isDiscoveryOnly {
                guard let files = try? target.access.listFiles() else { continue }
                for name in files where name.hasSuffix(GestaltViewModel.modelAssetDisabledSuffix) {
                    let original = String(name.dropLast(GestaltViewModel.modelAssetDisabledSuffix.count))
                    do {
                        try target.access.renameEntry(name, toName: original)
                        restored += 1
                    } catch {
                        modelAssetReports.append("⚠︎ \(target.id): could not restore \(name) — \(error.localizedDescription)")
                    }
                }
            }
            modelAssetHiddenCount = max(0, modelAssetHiddenCount - restored)
            notice = GestaltNotice(
                kind: .repaired,
                message: String(localized: "Restored \(restored) model asset bundle(s). Fully restart the iPhone for the asset system to pick them up.")
            )
        } catch {
            report(error)
        }
    }

    // MARK: Device Doctor
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
            save(pending, expectedIdentity: nil,
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
            // Removing the AI activation keys also closes the CacheData gate:
            // restore the pre-unlock blob from a same-CacheUUID backup so the
            // capability surface does not linger half-open.
            if plan.proposals.contains(where: { DeviceIdentityAudit.siriAIKeys.contains($0.id) && $0.isRemoval }) {
                let backups = try cachedBackupPlists()
                if let originalCacheData = SiriAIYumUnlock.originalCacheData(current: pending, backups: backups) {
                    pending.setValue(originalCacheData, forKey: SiriAIYumUnlock.cacheDataKey)
                }
            }
            let expected = SiriAIIdentityRestore.values(DeviceIdentityAudit.identityKeys, in: pending)
            save(pending, 
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

    /// Post-save expectations for a two-stage unlock step.
    private struct YumExpectation {
        var verifyCapabilities: Bool
        var borrowedProduct: String?
        var requireIdentityUnchanged: Bool
        var requireGenerativeFlag: Bool = false
        var expectedCacheData: Data?
        /// Identity keys the experimental toggles manage — excluded from the
        /// unchanged-identity comparison because they are verified separately.
        var excludeIdentityKeys: [String] = []
    }

    private func save(
        _ pendingPlist: GestaltPlist,
        expectedIdentity: NSDictionary? = nil,
        identityKeys: [String]? = nil,
        expectedYum: YumExpectation? = nil,
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
            if expectedIdentity != nil || expectedYum != nil {
                guard let originalDictionary = try PropertyListSerialization.propertyList(from: originalData, format: nil) as? [String: Any],
                      originalDictionary["CacheExtra"] is [String: Any] else {
                    throw GestaltEditError.invalidPlist
                }
                originalPlist = GestaltPlist(dict: originalDictionary)
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

            if let expectedYum {
                let cacheExtra = verifiedPlist.cacheExtra
                if let expectedCacheData = expectedYum.expectedCacheData {
                    guard (verifiedPlist.dict[SiriAIYumUnlock.cacheDataKey] as? Data) == expectedCacheData else {
                        throw GestaltEditError.verificationFailed
                    }
                }
                if expectedYum.verifyCapabilities {
                    guard cacheExtra[SiriAIYumUnlock.siriModeKey] as? Int == 2,
                          cacheExtra[SiriAIYumUnlock.generativeCapabilityKey] as? Int == 1,
                          cacheExtra[SiriAIYumUnlock.countryKey] as? String == "LL",
                          cacheExtra[SiriAIYumUnlock.regionKey] as? String == "LL/A",
                          (verifiedPlist.dict[SiriAIYumUnlock.cacheDataKey] as? Data)
                              .map(CacheDataUnlock.bitsReady) == true else {
                        throw GestaltEditError.verificationFailed
                    }
                }
                if let borrowed = expectedYum.borrowedProduct {
                    guard cacheExtra[DictationRepairRestore.productType] as? String == borrowed else {
                        throw GestaltEditError.verificationFailed
                    }
                }
                if expectedYum.requireGenerativeFlag {
                    guard cacheExtra[SiriAIYumUnlock.generativeCapabilityKey] as? Int == 1 else {
                        throw GestaltEditError.verificationFailed
                    }
                }
                if expectedYum.requireIdentityUnchanged {
                    // Capability-only stage 1: the hardware identity must be
                    // exactly as it was. Experimental-toggled keys are
                    // excluded here (they are verified separately by the
                    // expected-identity comparison over their own key list).
                    guard let original = originalPlist else {
                        throw GestaltEditError.verificationFailed
                    }
                    let unchangedKeys = DictationRepairRestore.keys
                        .filter { !expectedYum.excludeIdentityKeys.contains($0) }
                    guard SiriAIIdentityRestore.values(unchangedKeys, in: original)
                            .isEqual(SiriAIIdentityRestore.values(unchangedKeys, in: verifiedPlist)) else {
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
    case verificationFailed
    case eligibilityVerificationFailed
    case eligibilityTargetsUnavailable(String)
    case eligibilityInvalidPlist
    case eligibilityRollbackFailed(String)
    case eligibilityNoBackup
    case emptyModelName

    var errorDescription: String? {
        switch self {
        case .invalidPlist: String(localized: "The MobileGestalt plist is not a valid dictionary.")
        case .wrongDeviceBackup: String(localized: "This Siri AI identity backup belongs to a different device.")
        case .mismatchedIdentityBackup: String(localized: "This backup's device identity does not match this physical device. Repair requires a verified original backup of this device, taken before any device spoof.")
        case .invalidBackup: String(localized: "The backup is not a valid MobileGestalt plist.")
        case .verificationFailed: String(localized: "The MobileGestalt values after writing do not match the expected values.")
        case .eligibilityVerificationFailed: String(localized: "The eligibility plist after writing does not contain the applied override.")
        case .eligibilityTargetsUnavailable(let unavailable):
            String(format: String(localized: "No override was written because not every configured target is reachable. Unavailable targets:\n%@"), unavailable)
        case .eligibilityInvalidPlist:
            String(localized: "A target's existing eligibility file is not a readable dictionary, so nothing was written.")
        case .eligibilityRollbackFailed(let details):
            String(format: String(localized: "An eligibility write failed and rollback was incomplete. Check or restore the target files manually. Details:\n%@"), details)
        case .eligibilityNoBackup: String(localized: "No pre-apply eligibility backup was found, so the original state cannot be restored.")
        case .emptyModelName: String(localized: "The device model name cannot be empty.")
        }
    }
}
