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
    @Published var siriAIStageMode: SiriAIYumUnlock.StageMode = .capabilitiesOnly
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

    private func syncExperimentalSelection() {
        guard let cache = plist?.cacheExtra else { return }
        experimentalAIKeys = Set(ExperimentalAICapabilities.keys.filter {
            cache[$0.key] != nil
        }.map(\.key))
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
            || !experimentalAIKeys.isEmpty
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
            + (experimentalAIKeys.isEmpty ? 0 : 1)
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
                message: String(localized: "Enable Siri AI writes AI capability flags and opens the CacheData eligibility gate; the Borrow mode also swaps the ProductType temporarily, which can affect Face ID and dictation until Finish. On iPhone 15-class devices the new Siri did not engage on iOS 27.2.1, and dictation may wedge until the AI keys are removed again. Tap Apply to write — a backup is saved automatically.")
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
                 expectedYum: YumExpectation(verifyCapabilities: true, borrowedProduct: nil, requireIdentityUnchanged: false),
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
                    + (siriAIStageMode == .borrow ? " · " + String(localized: "Borrow") : ""))
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
            let stagedSiriAI = stagesSiriAI
            let stagedBorrow = siriAIStageMode == .borrow
            if stagedSiriAI {
                let machine = AIRegionProfile.machineIdentifier
                pending = try SiriAIYumUnlock.stageOne(
                    plist: pending,
                    machine: machine,
                    expectedBoard: DeviceIdentityAudit.expectedBoard(for: machine),
                    expectedCPU: DeviceIdentityAudit.expectedCPU(for: machine),
                    borrowProduct: stagedBorrow ? yumBorrowProduct : nil)
            }
            // Experimental AI capability keys: reconcile the cache to the
            // toggled target state (selected → write 1, unselected → remove).
            if !experimentalAIKeys.isEmpty
                || ExperimentalAICapabilities.allKeys.contains(where: { pending.cacheExtra[$0] != nil }) {
                for key in ExperimentalAICapabilities.allKeys {
                    if experimentalAIKeys.contains(key) {
                        if pending.cacheExtra[key] == nil {
                            pending.setCacheExtra(1, forKey: key)
                        }
                    } else if pending.cacheExtra[key] != nil {
                        pending.removeCacheExtraValue(forKey: key)
                    }
                }
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
            let experimentalExpected: NSDictionary? = experimentalAIKeys.isEmpty
                ? nil
                : NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: experimentalAIKeys.map { ($0, 1) }))
            let experimentalKeysList = experimentalAIKeys.isEmpty
                ? nil
                : ExperimentalAICapabilities.allKeys
            let expectedCacheData: Data? = cacheDataBitChanges.isEmpty
                ? nil
                : (pending.dict[SiriAIYumUnlock.cacheDataKey] as? Data)
            save(pending,
                 expectedIdentity: experimentalExpected,
                 identityKeys: experimentalKeysList,
                 expectedYum: stagedSiriAI
                    ? YumExpectation(verifyCapabilities: true,
                                     borrowedProduct: stagedBorrow ? yumBorrowProduct : nil,
                                     requireIdentityUnchanged: !stagedBorrow,
                                     expectedCacheData: expectedCacheData,
                                     excludeIdentityKeys: experimentalAIKeys.isEmpty
                                        ? [] : ExperimentalAICapabilities.allKeys)
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

    func probeAIEligibility() {
        guard !eligibilityProbed, selectedDevice == .iPhone else { return }
        eligibilityProbed = true
        var reports: [String] = []
        var reachable = 0
        for target in eligibilityTargets {
            do {
                try target.connect()
                let files = (try? target.listFiles()) ?? []
                reachable += 1
                let fileSummary = (files?.isEmpty == false)
                    ? ": " + (files ?? []).joined(separator: ", ")
                    : " (empty)"
                reports.append("✓ \(target.displayName) — reachable, \(files?.count ?? 0) file(s)\(fileSummary)")
            } catch {
                reports.append("✗ \(target.displayName) — \(error.localizedDescription)")
            }
        }
        eligibilityReachableCount = reachable
        eligibilityTargetReports = reports
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
            probeAIEligibility()
            guard eligibilityReachableCount > 0 else {
                throw GestaltEditError.eligibilityNoReachableTarget
            }
            let languageCodes = languageText
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map(String.init)
                .filter { !$0.isEmpty }
            for target in eligibilityTargets {
                let exists = target.plistFileExists
                let originalData: Data? = exists ? try target.readData() : nil
                try EligibilityBackupStore.save(original: originalData, for: target.displayName)
                let existing: [String: Any]? = originalData.flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
                }
                let pending = fullEligibilityOverride(languageCodes: languageCodes, mergingInto: existing)
                try target.savePlist(pending)
                guard let verification = try? target.readEligibility() as? [String: Any],
                      AIEligibilityOverride.isApplied(verification) else {
                    throw GestaltEditError.eligibilityVerificationFailed
                }
            }
            notice = GestaltNotice(
                kind: .saved,
                message: String(localized: "AI feature eligibility override written and verified on all reachable eligibility targets. Fully restart the iPhone, then test: the Apple Intelligence settings page, Writing Tools (e.g. in Notes), the ChatGPT extension in Siri, and dictation. Restore Original Eligibility reverts every target — the pre-apply state is backed up automatically.")
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
                    try target.removeEligibility()
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
                } else if expectedYum.requireIdentityUnchanged {
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
    case eligibilityNoReachableTarget
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
        case .eligibilityNoReachableTarget: String(localized: "No eligibility target is reachable with the current exploit class on this build.")
        case .eligibilityNoBackup: String(localized: "No pre-apply eligibility backup was found, so the original state cannot be restored.")
        case .emptyModelName: String(localized: "The device model name cannot be empty.")
        }
    }
}
