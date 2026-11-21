import Foundation
import Darwin

// MARK: - Device Identity Doctor
//
// Read-only audit comparing the device identity stored in the MobileGestalt
// cache against the values the running hardware reports for itself (kernel
// sysctls, the IOKit device tree and a built-in device database). Editors
// that enable Siri AI on unsupported devices historically wrote a fake
// ProductType / HardwareModel / CPUModel into the cache; while those values
// are present, the speech stack (dictation, spoken Siri) and Face ID select
// resources for hardware that does not exist and stop working.
//
// The doctor finds that damage with or without a pre-spoof backup, produces
// a shareable report, and builds a verified fix plan. Every proposed value
// comes from the hardware itself, a verified clean backup, or the built-in
// device database — never from guesses — and every write is confirmed by the
// user and re-verified after saving.
enum DeviceIdentityAudit {
    struct DeviceProfile: Equatable {
        let name: String
        let boards: [String]
        let cpuModel: String?
    }

    // MARK: Audited keys

    static let productType = DictationRepairRestore.productType        // ProductType
    static let thinningProductType = DictationRepairRestore.thinningProductType // ThinningProductType
    static let gsDeviceName = DictationRepairRestore.gsDeviceName      // GSDeviceName
    static let hardwareModel = DictationRepairRestore.hardwareModel    // TargetSubType
    static let hardwareModelStr = DictationRepairRestore.hardwareModelStr // HWModelStr
    static let cpuModel = DictationRepairRestore.cpuModel              // HardwarePlatform
    static let regulatoryModel = DictationRepairRestore.modelNumber    // RegulatoryModelNumber
    static let siriOnDevice = DictationRepairRestore.siriOnDevice      // DeviceSupportsSiriUnderstandingOnDevice
    static let marketingName = DictationRepairRestore.marketingName    // marketing-name
    static let physicalHardwareName = DictationRepairRestore.physicalHardwareName // PhysicalHardwareNameString

    /// Every identity key the doctor writes and re-verifies after a repair.
    static let identityKeys = [
        productType, thinningProductType, gsDeviceName,
        hardwareModel, hardwareModelStr, cpuModel,
        regulatoryModel, siriOnDevice, marketingName, physicalHardwareName
    ]

    // MARK: Siri AI residue keys

    /// Keys written by Siri AI editors (this fork and third-party ones) to
    /// force-enable the generative pipeline. A stock cache never stores them;
    /// while they are present the Siri stack may keep running a pipeline this
    /// device cannot complete, which wedges dictation and spoken Siri even
    /// when the device identity itself is clean.
    static let siriAIKeys = [
        "A62OafQ85EJAiiqKn4agtg",   // Generative Siri capability flag
        "a3n5T9sFtlyQ74NEp9ESxg",   // SiriMode
        "eX0KGm4RpWq7bZV1tY8s3A", // iOS 27 expansion flag
        "4pPl3nt3LL1g3nc3All0wd",   // persistence triple
        "4pPl3nt3LL1g3nc3Supptd",
        "4pPl3nt3LL1g3nc3M1nRAm",
    ]

    /// Region keys Siri AI editors rewrite to LL/LL/A for restricted regions.
    /// LL is also the genuine value for US-region devices, so these are
    /// reported without being treated as proof of an edit.
    static let regionOverrideKeys = [
        "h63QSdBCiT/z0WU6rdQv6Q",   // DeviceRegionCode
        "yK+xavymRGZ3xWc1tb8XDg",   // Region sales code
        "zHeENZu+wbg7PUprwNwBWg",   // Secondary region code
    ]

    struct ResidueKey {
        let key: String
        let title: String
        let note: String
    }

    private static let siriAIResidueDefinitions: [ResidueKey] = [
        ResidueKey(
            key: "A62OafQ85EJAiiqKn4agtg",
            title: "Siri AI Capability Flag",
            note: "Written by Siri AI editors to force-enable generative Siri; stock caches never store it. With the new Siri runtime unavailable, this flag can wedge dictation and spoken Siri."
        ),
        ResidueKey(
            key: "a3n5T9sFtlyQ74NEp9ESxg",
            title: "Siri Mode",
            note: "Written by Siri AI editors (value 2 selects the new Siri pipeline). Removing it returns the speech stack to the standard pipeline."
        ),
        ResidueKey(
            key: "eX0KGm4RpWq7bZV1tY8s3A",
            title: "iOS 27 Generative Experiences Flag",
            note: "Part of iOS 27 spoof bundles: it makes Image Playground and the dedicated Siri app appear. Keeping it after the identity revert (together with the persistence keys below) is what lets the downloaded apps survive; removing it hides the apps again."
        ),
        ResidueKey(
            key: "4pPl3nt3LL1g3nc3All0wd",
            title: "Apple Intelligence Allowed Device",
            note: "Persistence key of the iOS 27 unlock sequence. Keeping it (with Supported Device and Minimum RAM) is what lets Image Playground and the dedicated Siri app survive the identity revert. Remove all three only if you want the AI feature surface gone or dictation stays wedged."
        ),
        ResidueKey(
            key: "4pPl3nt3LL1g3nc3Supptd",
            title: "Apple Intelligence Supported Device",
            note: "Second persistence key of the iOS 27 unlock sequence. Same guidance as Allowed Device: keep all three while you use the AI features, remove all three to revert."
        ),
        ResidueKey(
            key: "4pPl3nt3LL1g3nc3M1nRAm",
            title: "Apple Intelligence Minimum RAM",
            note: "Third persistence key of the iOS 27 unlock sequence; genuine unlock bundles store the value 6. Same guidance as Allowed Device."
        ),
    ]

    private static let regionResidueDefinitions: [ResidueKey] = [
        ResidueKey(
            key: "h63QSdBCiT/z0WU6rdQv6Q",
            title: "Device Region Code",
            note: "Siri AI editors write LL to bypass region restrictions, but LL is also the genuine value for US-region devices. Remove it only if this device's real region is different."
        ),
        ResidueKey(
            key: "yK+xavymRGZ3xWc1tb8XDg",
            title: "Region Sales Code",
            note: "Siri AI editors write LL/A to bypass region restrictions, but LL/A is also the genuine value for US-region devices. Remove it only if this device's real region is different."
        ),
        ResidueKey(
            key: "zHeENZu+wbg7PUprwNwBWg",
            title: "Secondary Region Code",
            note: "Region marker rewritten by Siri AI editors for restricted regions. Removing it lets iOS recompute the real value after restart."
        ),
    ]

    struct Entry: Identifiable, Equatable {
        enum Status: Equatable { case match, mismatch, review, residue }

        let id: String
        let title: String
        let cachedValue: String?
        let expectedValue: String?
        let status: Status
        let note: String?
    }

    struct Report: Equatable {
        let machineIdentifier: String
        let kernelHardwareModel: String?
        let ioKitPlatform: String?
        let entries: [Entry]
        let cacheKeyCount: Int
        let cacheInventoryText: String
        let cacheDataBitsReady: Bool

        var isSpoofed: Bool { entries.contains { $0.status == .mismatch } }
        var spoofedEntries: [Entry] { entries.filter { $0.status == .mismatch } }

        /// Stage-2 end state of the two-stage unlock: real identity restored,
        /// capability keys and patched CacheData bits intentionally present.
        var isStageTwoUnlockActive: Bool {
            !isSpoofed && hasSiriAIResidue && cacheDataBitsReady
        }

        /// Leftover Siri AI activation keys (capability flag, SiriMode) still
        /// stored by an earlier editor run. With a clean identity these are
        /// the leading remaining cause of a wedged speech stack.
        var siriAIResidueEntries: [Entry] {
            entries.filter { DeviceIdentityAudit.siriAIKeys.contains($0.id) && $0.cachedValue != nil }
        }

        var hasSiriAIResidue: Bool { !siriAIResidueEntries.isEmpty }

        /// Region values currently sitting in the cache, shown so the user
        /// can spot an editor override (or confirm the genuine US value).
        var regionOverrideEntries: [Entry] {
            entries.filter { DeviceIdentityAudit.regionOverrideKeys.contains($0.id) && $0.cachedValue != nil }
        }

        /// Everything the cache stores that is not a Siri AI residue row.
        var identityEntries: [Entry] {
            let residue = Set(DeviceIdentityAudit.siriAIKeys + DeviceIdentityAudit.regionOverrideKeys)
            return entries.filter { !residue.contains($0.id) }
        }

        /// Every residue row (activation keys plus region values) for the UI.
        var residueEntries: [Entry] {
            entries.filter {
                DeviceIdentityAudit.siriAIKeys.contains($0.id) || DeviceIdentityAudit.regionOverrideKeys.contains($0.id)
            }
        }

        var reportText: String {
            var lines: [String] = [
                "GestaltEdit Device Doctor",
                "Device (kernel hw.machine): \(machineIdentifier)"
            ]
            if let kernelHardwareModel {
                lines.append("Kernel board (hw.model): \(kernelHardwareModel)")
            }
            if let ioKitPlatform {
                lines.append("IOKit platform: \(ioKitPlatform)")
            }
            lines.append("")
            lines.append("MobileGestalt cache audit (\(cacheKeyCount) keys stored):")
            for entry in entries {
                let stored = entry.cachedValue ?? "(not stored)"
                let expected = entry.expectedValue.map { " / expected \($0)" } ?? ""
                let verdict: String
                switch entry.status {
                case .match: verdict = "OK"
                case .mismatch: verdict = "MISMATCH"
                case .review: verdict = "REVIEW"
                case .residue: verdict = "SIRI AI RESIDUE"
                }
                lines.append("- \(entry.title): \(stored)\(expected) [\(verdict)]")
            }
            lines.append("")
            lines.append("CacheData AI eligibility bits: \(cacheDataBitsReady ? "READY (unlocked)" : "NOT PATCHED — the CacheData gate is closed")")
            lines.append("")
            if isSpoofed && hasSiriAIResidue {
                lines.append("Verdict: STAGE 1 BORROW ACTIVE (\(spoofedEntries.count) identity mismatches plus Siri AI keys).")
                lines.append("The two-stage unlock is mid-flight: the ProductType is borrowed, the US region, SiriMode 2 and the generative capability flag are written, and the CacheData gate is \(cacheDataBitsReady ? "open" : "NOT patched — Stage 1 did not complete"). This is the EXPECTED state between Stage 1 and Stage 2.")
                lines.append("Do NOT repair anything now — the resource download needs this state. Fully restart the iPhone, let the Apple resources download (Siri language must MATCH the iPhone language — both must be a supported Apple Intelligence language), and only when the download is done run Stage 2 (Tools → Siri AI Unlock → Restore Real Identity), restart, and test Siri by voice.")
                lines.append("NEVER open Settings → Siri (or Apple Intelligence & Siri) after Stage 2 — that page re-runs eligibility against the restored hardware and can invalidate the downloaded resources.")
            } else if isSpoofed {
                lines.append("Verdict: DEVICE IDENTITY SPOOFED (\(spoofedEntries.count) mismatches).")
                lines.append("This is what breaks dictation, spoken Siri and Face ID.")
                lines.append("Fix: Restore tab → Device Doctor → Fix Detected Errors, or Repair Dictation & Face ID from the original backup, then restart.")
            } else if isStageTwoUnlockActive {
                lines.append("Verdict: SIRI AI UNLOCK ACTIVE — real identity restored, capability keys and open CacheData gate intentionally present.")
                lines.append("This is the finished two-stage unlock: Face ID and dictation run on the real hardware again while the Siri AI capability surface (US region, SiriMode 2, generative capability flag, CacheData gate) stays unlocked. These keys are NOT damage — do not remove them unless you want to revert the unlock entirely.")
                lines.append("IMPORTANT: never open Settings → Siri (or Apple Intelligence & Siri) now. Opening that page re-runs device eligibility against the real hardware and can invalidate the downloaded resources and strip the capability keys — the documented failure mode. Test Siri by voice (side button / voice trigger), and check Face ID and dictation.")
                lines.append("If a dictation language is wedged, remove it from Settings → General → Keyboard → Dictation Languages, restart, then re-add it on Wi-Fi so iOS downloads fresh speech resources for the restored identity.")
                lines.append("To revert the unlock entirely: Fix Detected Errors → enable Remove Siri AI Activation Keys — the pre-unlock CacheData gate is restored from the automatic backup alongside the key removal.")
            } else if hasSiriAIResidue {
                lines.append("Verdict: device identity matches, but Siri AI activation keys are still stored in the cache.")
                lines.append("These keys (capability flag, SiriMode, expansion and persistence keys) were written by a Siri AI editor. They tell the Siri stack to run the generative pipeline, which this device cannot complete — a known cause of dictation and spoken Siri staying broken even though the identity is clean.")
                lines.append("If you just finished the AI Expansion revert (Restore Identity · Keep AI Keys) and are waiting for Image Playground or the Siri app, these keys are supposed to be here — keep them and see the Siri AI Feature Setup Guide in Tools → Region → More Siri AI Features.")
                lines.append("Fix: Restore tab → Device Doctor → Fix Detected Errors → enable Remove Siri AI Activation Keys, then restart the iPhone. Skip the AI-key removal if Image Playground and the Siri app are currently working and you want to keep them — the persistence keys are what keep them alive; in that case only fix a spoofed identity, never the AI keys.")
                lines.append("Afterwards, refresh each failing dictation language: remove it from Settings → General → Keyboard → Dictation Languages, restart, then re-add it on Wi-Fi so iOS re-downloads fresh speech resources for the repaired identity. Dictation working in one language while failing in another is the signature of speech resources that were downloaded while the old keys were still active.")
                lines.append("Siri AI can be re-enabled afterwards from the Siri AI tab (dictation-safe mode).")
            } else {
                lines.append("Verdict: cache is clean — no MobileGestalt spoof remains and no Siri AI activation keys are stored.")
                lines.append("Siri AI activation trace: none. If you ran Tools → Region → Enable Siri AI → Apply, judge by THIS report, not by About: About does not reliably reflect the borrow on iOS 27.2 (it can keep showing the real model name even while the borrow is active). A trace of none after an apply means the write never landed in this cache or iOS rebuilt it — the version you applied must be 2.6.2 or newer, because 2.6.0/2.6.1 resolved to a no-op on this device while still reporting success. Apply once more with the new build, note whether the app reports Saved or an error, scan again immediately afterwards (before any restart), and share what you saw.")
                lines.append("If dictation still fails, the cause is outside MobileGestalt. Check in order:")
                lines.append("1. Settings → General → Keyboard → Enable Dictation is on.")
                lines.append("2. Settings → General → Keyboard → Dictation Languages includes your language.")
                lines.append("3. Dictation works in one language but fails in another: the failing language's speech resources were downloaded while the spoof or AI keys were active. Remove that language from Settings → General → Keyboard → Dictation Languages, restart the iPhone, then re-add it on Wi-Fi so iOS downloads fresh resources.")
                lines.append("4. Settings → Screen Time → Content & Privacy Restrictions → Allowed Apps and Siri & Dictation are not restricted.")
                lines.append("5. Settings → Siri & Search: Siri is on.")
                lines.append("6. Full restart (power off and on) after any cache change — speech daemons keep their state until then.")
                lines.append("7. Last resort: Device Doctor → Factory Cache Reset rebuilds a brand-new native cache (removes all MobileGestalt edits).")
            }
            lines.append("")
            lines.append(cacheInventoryText)
            return lines.joined(separator: "\n")
        }
    }

    struct ChangeProposal: Identifiable, Equatable {
        let id: String
        let title: String
        let currentValue: String?
        let proposedValue: String?
        let isRemoval: Bool
        let editable: Bool
        let reason: String
    }

    struct FixPlan: Equatable {
        let machineIdentifier: String
        let proposals: [ChangeProposal]

        var hasChanges: Bool { !proposals.isEmpty }
    }

    // MARK: Audit

    /// - Parameters:
    ///   - kernelHardwareModel: hw.model sysctl value (board configuration).
    ///   - ioKitPlatform: IOKit "platform-name" (HardwarePlatform truth).
    ///   - backupIdentity: identity values from a local backup that matches
    ///     the physical device, used when the kernel cannot answer a key.
    static func audit(
        _ plist: GestaltPlist,
        machine: String = AIRegionProfile.machineIdentifier,
        kernelHardwareModel: String? = nil,
        ioKitPlatform: String? = nil,
        backupIdentity: NSDictionary? = nil
    ) -> Report {
        let cache = plist.cacheExtra
        func cachedString(_ key: String) -> String? {
            guard let value = cache[key] else { return nil }
            return PlistValueInfo.encode(value, as: PlistValueKind.kind(of: value))
        }

        let normalizedMachine = normalizedIdentifier(machine)
        let profile = normalizedMachine.isEmpty ? nil : deviceProfiles[normalizedMachine]

        // Board configuration: kernel > backup > device database.
        let kernelBoard = validBoard(kernelHardwareModel)
        let backupBoard = validBoard(backupIdentity?[hardwareModel] as? String)
            ?? validBoard(backupIdentity?[hardwareModelStr] as? String)
        let boardExpected = kernelBoard ?? backupBoard ?? profile?.boards.first
        let boardSource = kernelBoard != nil
            ? String(localized: "reported by the kernel")
            : backupBoard != nil
            ? String(localized: "from a verified backup")
            : (profile?.boards.first != nil ? String(localized: "from the device database") : nil)

        // SoC platform: IOKit > backup > device database.
        let ioKitCPU = validPlatform(ioKitPlatform)
        let backupCPU = validPlatform(backupIdentity?[cpuModel] as? String)
        let cpuExpected = ioKitCPU ?? backupCPU ?? profile?.cpuModel
        let cpuSource = ioKitCPU != nil
            ? String(localized: "reported by the hardware (IOKit device tree)")
            : backupCPU != nil
            ? String(localized: "from a verified backup")
            : (profile?.cpuModel != nil ? String(localized: "from the device database") : nil)

        let nameExpected = profile?.name
        let unknownDevice = profile == nil && kernelBoard == nil && ioKitCPU == nil

        var entries: [Entry] = []

        func productEntry(_ key: String, _ title: String) {
            let cached = cachedString(key)
            let status: Entry.Status
            var note: String?
            if machine.isEmpty {
                status = .review
                note = String(localized: "The kernel did not report this device's machine identifier.")
            } else if let cached, normalizedIdentifier(cached) == normalizedIdentifier(machine) {
                status = .match
            } else if cached != nil {
                status = .mismatch
                note = String(localized: "Stored value describes a different device than the one the kernel reports.")
            } else {
                status = .review
                note = String(localized: "Not stored in the cache; the system then answers from the hardware, which is fine.")
            }
            entries.append(Entry(id: key, title: title, cachedValue: cached,
                                 expectedValue: machine.isEmpty ? nil : machine,
                                 status: status, note: note))
        }

        func valueEntry(_ key: String, _ title: String, expected: String?, source: String?, exact: Bool) {
            let cached = cachedString(key)
            let matches: Bool
            if let cached, let expected {
                matches = exact ? cached == expected : normalizedIdentifier(cached) == normalizedIdentifier(expected)
            } else {
                matches = false
            }
            let status: Entry.Status
            var note: String?
            if let cached, let expected, matches {
                status = .match
            } else if cached != nil, expected != nil {
                status = .mismatch
                if let source {
                    note = String(localized: "Stored value differs from the hardware truth (\(source)).")
                } else {
                    note = String(localized: "Stored value differs from the hardware truth.")
                }
            } else if cached == nil {
                status = .review
                note = String(localized: "Not stored in the cache.")
            } else {
                status = .review
                note = unknownDevice
                    ? String(localized: "This device is not in the built-in database, so no expected value could be derived.")
                    : nil
            }
            entries.append(Entry(id: key, title: title, cachedValue: cached,
                                 expectedValue: expected, status: status, note: note))
        }

        productEntry(productType, String(localized: "Product Type"))
        productEntry(thinningProductType, String(localized: "Thinning Product Type"))
        // GS Device Name stores the device FAMILY name ("iPhone", "iPad") on
        // stock devices — never the machine identifier. Comparing it to
        // hw.machine flagged every healthy iPhone as "spoofed", so the
        // expectation here is the family the kernel reports.
        do {
            let cached = cachedString(gsDeviceName)
            let family = deviceFamily(for: machine)
            let status: Entry.Status
            var note: String?
            if machine.isEmpty {
                status = .review
                note = String(localized: "The kernel did not report this device's machine identifier.")
            } else if let cached,
                      normalizedIdentifier(cached) == normalizedIdentifier(family)
                        || normalizedIdentifier(cached) == normalizedIdentifier(machine) {
                status = .match
            } else if cached != nil {
                status = .mismatch
                note = String(localized: "Stored value describes a different device than the one the kernel reports.")
            } else {
                status = .review
                note = String(localized: "Not stored in the cache; the system then answers from the hardware, which is fine.")
            }
            entries.append(Entry(id: gsDeviceName, title: String(localized: "GS Device Name"),
                                 cachedValue: cached, expectedValue: machine.isEmpty ? nil : family,
                                 status: status, note: note))
        }
        valueEntry(hardwareModel, String(localized: "Hardware Model"),
                   expected: boardExpected, source: boardSource, exact: true)
        valueEntry(hardwareModelStr, String(localized: "Hardware Model String"),
                   expected: boardExpected, source: boardSource, exact: true)
        valueEntry(cpuModel, String(localized: "CPU Model"),
                   expected: cpuExpected, source: cpuSource, exact: true)

        // Regulatory model number: no kernel source; check the format and let
        // the user confirm or correct it against Settings → About.
        do {
            let cached = cachedString(regulatoryModel)
            if let cached, validRegulatory(cached) {
                entries.append(Entry(
                    id: regulatoryModel,
                    title: String(localized: "Regulatory Model Number"),
                    cachedValue: cached, expectedValue: nil, status: .match,
                    note: String(localized: "Format looks valid. Confirm it against Settings → General → About → Model Number (tap the row to show the A-number).")
                ))
            } else if let cached {
                entries.append(Entry(
                    id: regulatoryModel,
                    title: String(localized: "Regulatory Model Number"),
                    cachedValue: cached, expectedValue: nil, status: .mismatch,
                    note: String(localized: "Does not look like an Apple regulatory model number (A1234). Enter the real value from Settings → General → About when fixing.")
                ))
            } else {
                entries.append(Entry(
                    id: regulatoryModel,
                    title: String(localized: "Regulatory Model Number"),
                    cachedValue: nil, expectedValue: nil, status: .review,
                    note: String(localized: "Not stored in the cache.")
                ))
            }
        }

        // On-device Siri understanding: device-specific capability; presence
        // alone is not proof of tampering, so it is offered as an optional fix.
        do {
            let cached = cachedString(siriOnDevice)
            if cached != nil {
                entries.append(Entry(
                    id: siriOnDevice,
                    title: String(localized: "On-Device Siri Understanding"),
                    cachedValue: cached, expectedValue: nil, status: .review,
                    note: String(localized: "Belongs to the original hardware. If a spoofing editor added it, removing it can restore the on-device speech pipeline; offered as an optional fix.")
                ))
            } else {
                entries.append(Entry(
                    id: siriOnDevice,
                    title: String(localized: "On-Device Siri Understanding"),
                    cachedValue: nil, expectedValue: nil, status: .review,
                    note: String(localized: "Not stored in the cache, as on devices that never shipped this capability.")
                ))
            }
        }

        valueEntry(marketingName, String(localized: "Marketing Name"),
                   expected: nameExpected, source: nil, exact: true)
        valueEntry(physicalHardwareName, String(localized: "Physical Hardware Name"),
                   expected: nameExpected, source: nil, exact: true)

        // Leftover Siri AI editor keys. The capability flag and SiriMode are
        // the leading suspects when the identity is clean but dictation is
        // still broken: they keep the Siri stack in a pipeline the device
        // cannot complete. Region values are only surfaced when they hold the
        // editor override (LL/LL/A), which doubles as the genuine US value.
        func residueEntry(_ definition: ResidueKey, _ status: Entry.Status) {
            guard cache[definition.key] != nil else { return }
            entries.append(Entry(
                id: definition.key,
                title: String(localized: String.LocalizationValue(definition.title)),
                cachedValue: cachedString(definition.key),
                expectedValue: nil,
                status: status,
                note: String(localized: String.LocalizationValue(definition.note))
            ))
        }
        for definition in siriAIResidueDefinitions {
            residueEntry(definition, .residue)
        }
        for definition in regionResidueDefinitions {
            guard let regionValue = cache[definition.key] as? String else { continue }
            let normalized = regionValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard normalized == "LL" || normalized == "LL/A" else { continue }
            residueEntry(definition, .review)
        }

        // Full inventory: keeps unknown or foreign edits visible in the
        // shareable report instead of hiding behind the audited key set.
        var inventoryLines: [String] = ["Full cache inventory:"]
        for key in plist.cacheExtraKeys {
            guard let value = plist.cacheExtra[key] else { continue }
            var encoded = PlistValueInfo.encode(value, as: PlistValueKind.kind(of: value))
            if encoded.count > 120 {
                encoded = String(encoded.prefix(120)) + "…"
            }
            inventoryLines.append("- \(key) = \(encoded)")
        }

        return Report(machineIdentifier: machine,
                      kernelHardwareModel: kernelBoard,
                      ioKitPlatform: ioKitCPU,
                      entries: entries,
                      cacheKeyCount: plist.cacheExtra.count,
                      cacheInventoryText: inventoryLines.joined(separator: "\n"),
                      cacheDataBitsReady: (plist.dict["CacheData"] as? Data).map { CacheDataUnlock.bitsReady($0) } ?? false)
    }

    // MARK: Fix plan

    /// Builds the write plan from a report. `regulatoryModelOverride` is the
    /// user-entered A-number (empty when the stored one is fine);
    /// `removeSiriOnDevice` enables the optional capability-flag removal;
    /// `removeSiriAIKeys` removes leftover Siri AI activation keys;
    /// `removeRegionOverrides` removes the LL/LL/A region override.
    static func fixPlan(
        from report: Report,
        removeSiriOnDevice: Bool = false,
        removeSiriAIKeys: Bool = false,
        removeRegionOverrides: Bool = false,
        regulatoryModelOverride: String? = nil
    ) -> FixPlan {
        guard !normalizedIdentifier(report.machineIdentifier).isEmpty else {
            return FixPlan(machineIdentifier: report.machineIdentifier, proposals: [])
        }

        var proposals: [ChangeProposal] = []
        func addString(_ entry: Entry, proposed: String?) {
            guard let proposed, entry.cachedValue != proposed else { return }
            proposals.append(ChangeProposal(
                id: entry.id, title: entry.title,
                currentValue: entry.cachedValue, proposedValue: proposed,
                isRemoval: false, editable: false,
                reason: entry.note ?? String(localized: "Restored to match this hardware.")
            ))
        }

        for entry in report.entries where entry.id == productType
            || entry.id == thinningProductType {
            addString(entry, proposed: report.machineIdentifier)
        }
        // GS Device Name is repaired to the family name ("iPhone"/"iPad"),
        // never the machine identifier — that value is normal on stock caches
        // and rewriting it would CREATE the mismatch the doctor warns about.
        if let gsEntry = report.entries.first(where: { $0.id == gsDeviceName }),
           gsEntry.cachedValue != deviceFamily(for: report.machineIdentifier) {
            addString(gsEntry, proposed: deviceFamily(for: report.machineIdentifier))
        }
        for entry in report.entries where entry.id == hardwareModel
            || entry.id == hardwareModelStr || entry.id == cpuModel
            || entry.id == marketingName || entry.id == physicalHardwareName {
            addString(entry, proposed: entry.expectedValue)
        }

        if let override = regulatoryModelOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           validRegulatory(override),
           let entry = report.entries.first(where: { $0.id == regulatoryModel }),
           entry.cachedValue != override {
            proposals.append(ChangeProposal(
                id: regulatoryModel,
                title: String(localized: "Regulatory Model Number"),
                currentValue: entry.cachedValue, proposedValue: override,
                isRemoval: false, editable: true,
                reason: String(localized: "Value entered manually from Settings → General → About.")
            ))
        }

        if removeSiriOnDevice,
           let entry = report.entries.first(where: { $0.id == siriOnDevice }),
           entry.cachedValue != nil {
            proposals.append(ChangeProposal(
                id: siriOnDevice,
                title: String(localized: "On-Device Siri Understanding"),
                currentValue: entry.cachedValue, proposedValue: nil,
                isRemoval: true, editable: false,
                reason: String(localized: "Removes the capability flag so the speech pipeline falls back to the real hardware answers.")
            ))
        }

        if removeSiriAIKeys {
            for entry in report.siriAIResidueEntries {
                proposals.append(ChangeProposal(
                    id: entry.id, title: entry.title,
                    currentValue: entry.cachedValue, proposedValue: nil,
                    isRemoval: true, editable: false,
                    reason: String(localized: "Removes the leftover Siri AI activation flag so the speech stack runs the standard pipeline again. Siri AI can be re-enabled later from the Siri AI tab.")
                ))
            }
        }

        if removeRegionOverrides {
            for entry in report.regionOverrideEntries {
                proposals.append(ChangeProposal(
                    id: entry.id, title: entry.title,
                    currentValue: entry.cachedValue, proposedValue: nil,
                    isRemoval: true, editable: false,
                    reason: String(localized: "Removes the stored region override; iOS recomputes the device's real region after restart.")
                ))
            }
        }

        return FixPlan(machineIdentifier: report.machineIdentifier, proposals: proposals)
    }

    /// Applies a plan to a copy of the current plist. The caller is expected
    /// to save through the verified save path (automatic backup + re-read +
    /// expected-identity comparison).
    static func applying(_ plan: FixPlan, to plist: inout GestaltPlist) {
        for proposal in plan.proposals {
            if proposal.isRemoval {
                plist.removeCacheExtraValue(forKey: proposal.id)
            } else if let value = proposal.proposedValue {
                plist.setCacheExtra(value, forKey: proposal.id)
            }
        }
    }

    // MARK: Validation helpers

    /// Board configuration strings: D73AP, D52gAP, D331pAP, V64sAP, J410AP…
    static func validBoard(_ value: String?) -> String? {
        guard let value, !value.hasPrefix("iPhone"), !value.hasPrefix("iPad") else { return nil }
        return value.range(of: "^[A-Z]\\d{2,3}[a-zA-Z]{0,3}AP$", options: .regularExpression) == nil ? nil : value
    }

    /// SoC platform strings: t8130, t8140a…
    static func validPlatform(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.range(of: "^t\\d{4}[a-z]?$", options: .regularExpression) == nil ? nil : value
    }

    /// Apple regulatory model numbers: A2848…
    static func validRegulatory(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: "^A\\d{4}$", options: .regularExpression) != nil
    }

    /// "iPad16,3-B" → "iPad16,3"
    private static func normalizedIdentifier(_ product: String) -> String {
        String(product.split(separator: "-", maxSplits: 1).first ?? "")
    }

    /// Hardware-truth board configuration for a machine identifier, from the
    /// built-in device database. Used by the two-stage unlock to prove the
    /// cache carries the physical board before writing.
    static func expectedBoard(for machine: String) -> String? {
        deviceProfiles[normalizedIdentifier(machine)]?.boards.first
    }

    /// Hardware-truth SoC code for a machine identifier (nil when the
    /// database does not record one for this model).
    static func expectedCPU(for machine: String) -> String? {
        deviceProfiles[normalizedIdentifier(machine)]?.cpuModel
    }

    /// "iPhone15,4" → "iPhone", "iPad16,1" → "iPad" — the device family name
    /// GS Device Name stores on stock devices.
    static func deviceFamily(for machine: String) -> String {
        let prefix = machine.prefix(while: { !$0.isNumber })
        return prefix.isEmpty ? machine : String(prefix)
    }

    // Identifier -> marketing name, board configuration (HardwareModel /
    // TargetSubType) and HardwarePlatform (CPUModel). Source: appledb.dev
    // device database; CPU codes verified against theapplewiki chip pages.
    private static let deviceProfiles: [String: DeviceProfile] = [
        "iPad13,1": .init(name: "iPad Air (4th generation)", boards: ["J307AP"], cpuModel: "t8108"),
        "iPad13,2": .init(name: "iPad Air (4th generation)", boards: ["J308AP"], cpuModel: "t8108"),
        "iPad13,4": .init(name: "iPad Pro 11-inch (3rd generation)", boards: ["J517AP"], cpuModel: "t8103"),
        "iPad13,5": .init(name: "iPad Pro 11-inch (3rd generation) (1 or 2 TB)", boards: ["J517xAP"], cpuModel: "t8103"),
        "iPad13,6": .init(name: "iPad Pro 11-inch (3rd generation)", boards: ["J518AP"], cpuModel: "t8103"),
        "iPad13,7": .init(name: "iPad Pro 11-inch (3rd generation) (1 or 2 TB)", boards: ["J518xAP"], cpuModel: "t8103"),
        "iPad13,8": .init(name: "iPad Pro 12.9-inch (5th generation)", boards: ["J522AP"], cpuModel: "t8103"),
        "iPad13,9": .init(name: "iPad Pro 12.9-inch (5th generation) (1 or 2 TB)", boards: ["J522xAP"], cpuModel: "t8103"),
        "iPad13,10": .init(name: "iPad Pro 12.9-inch (5th generation)", boards: ["J523AP"], cpuModel: "t8103"),
        "iPad13,11": .init(name: "iPad Pro 12.9-inch (5th generation) (1 or 2 TB)", boards: ["J523xAP"], cpuModel: "t8103"),
        "iPad13,16": .init(name: "iPad Air (5th generation)", boards: ["J407AP"], cpuModel: "t8103"),
        "iPad13,17": .init(name: "iPad Air (5th generation)", boards: ["J408AP"], cpuModel: "t8103"),
        "iPad13,18": .init(name: "iPad (10th generation)", boards: ["J271AP"], cpuModel: "t8108"),
        "iPad13,19": .init(name: "iPad (10th generation)", boards: ["J272AP"], cpuModel: "t8108"),
        "iPad14,1": .init(name: "iPad mini (6th generation)", boards: ["J310AP"], cpuModel: "t8110"),
        "iPad14,2": .init(name: "iPad mini (6th generation)", boards: ["J311AP"], cpuModel: "t8110"),
        "iPad14,3": .init(name: "iPad Pro 11-inch (4th generation)", boards: ["J617AP"], cpuModel: "t8112"),
        "iPad14,4": .init(name: "iPad Pro 11-inch (4th generation)", boards: ["J618AP"], cpuModel: "t8112"),
        "iPad14,5": .init(name: "iPad Pro 12.9-inch (6th generation)", boards: ["J620AP"], cpuModel: "t8112"),
        "iPad14,6": .init(name: "iPad Pro 12.9-inch (6th generation)", boards: ["J621AP"], cpuModel: "t8112"),
        "iPad14,8": .init(name: "iPad Air 11-inch (M2)", boards: ["J507AP"], cpuModel: "t8112"),
        "iPad14,9": .init(name: "iPad Air 11-inch (M2)", boards: ["J508AP"], cpuModel: "t8112"),
        "iPad14,10": .init(name: "iPad Air 13-inch (M2)", boards: ["J537AP"], cpuModel: "t8112"),
        "iPad14,11": .init(name: "iPad Air 13-inch (M2)", boards: ["J538AP"], cpuModel: "t8112"),
        "iPad15,3": .init(name: "iPad Air 11-inch (M3)", boards: ["J607AP"], cpuModel: "t8122"),
        "iPad15,4": .init(name: "iPad Air 11-inch (M3)", boards: ["J608AP"], cpuModel: "t8122"),
        "iPad15,5": .init(name: "iPad Air 13-inch (M3)", boards: ["J637AP"], cpuModel: "t8122"),
        "iPad15,6": .init(name: "iPad Air 13-inch (M3)", boards: ["J638AP"], cpuModel: "t8122"),
        "iPad15,7": .init(name: "iPad (A16)", boards: ["J481AP"], cpuModel: "t8120"),
        "iPad15,8": .init(name: "iPad (A16)", boards: ["J482AP"], cpuModel: "t8120"),
        "iPad16,1": .init(name: "iPad mini (A17 Pro)", boards: ["J410AP"], cpuModel: "t8130"),
        "iPad16,2": .init(name: "iPad mini (A17 Pro)", boards: ["J411AP"], cpuModel: "t8130"),
        "iPad16,3": .init(name: "iPad Pro 11-inch (M4)", boards: ["J717AP"], cpuModel: nil),
        "iPad16,4": .init(name: "iPad Pro 11-inch (M4)", boards: ["J718AP"], cpuModel: nil),
        "iPad16,5": .init(name: "iPad Pro 13-inch (M4)", boards: ["J720AP"], cpuModel: nil),
        "iPad16,6": .init(name: "iPad Pro 13-inch (M4)", boards: ["J721AP"], cpuModel: nil),
        "iPad16,8": .init(name: "iPad Air 11-inch (M4)", boards: ["J707AP"], cpuModel: nil),
        "iPad16,9": .init(name: "iPad Air 11-inch (M4)", boards: ["J708AP"], cpuModel: nil),
        "iPad16,10": .init(name: "iPad Air 13-inch (M4)", boards: ["J737AP"], cpuModel: nil),
        "iPad16,11": .init(name: "iPad Air 13-inch (M4)", boards: ["J738AP"], cpuModel: nil),
        "iPad17,1": .init(name: "iPad Pro 11-inch (M5)", boards: ["J817AP"], cpuModel: nil),
        "iPad17,2": .init(name: "iPad Pro 11-inch (M5)", boards: ["J818AP"], cpuModel: nil),
        "iPad17,3": .init(name: "iPad Pro 13-inch (M5)", boards: ["J820AP"], cpuModel: nil),
        "iPad17,4": .init(name: "iPad Pro 13-inch (M5)", boards: ["J821AP"], cpuModel: nil),
        "iPad19,1": .init(name: "iPad mini (A20 Pro)", boards: ["J510AP"], cpuModel: nil),
        "iPad19,2": .init(name: "iPad mini (A20 Pro)", boards: ["J511AP"], cpuModel: nil),
        "iPhone11,2": .init(name: "iPhone XS", boards: ["D321AP"], cpuModel: "t8020"),
        "iPhone11,4": .init(name: "iPhone XS Max", boards: ["D331AP"], cpuModel: "t8020"),
        "iPhone11,6": .init(name: "iPhone XS Max", boards: ["D331pAP"], cpuModel: "t8020"),
        "iPhone11,8": .init(name: "iPhone XR", boards: ["N841AP"], cpuModel: "t8020"),
        "iPhone12,1": .init(name: "iPhone 11", boards: ["N104AP"], cpuModel: "t8030"),
        "iPhone12,3": .init(name: "iPhone 11 Pro", boards: ["D421AP"], cpuModel: "t8030"),
        "iPhone12,5": .init(name: "iPhone 11 Pro Max", boards: ["D431AP"], cpuModel: "t8030"),
        "iPhone12,8": .init(name: "iPhone SE (2nd generation)", boards: ["D79AP"], cpuModel: "t8030"),
        "iPhone13,1": .init(name: "iPhone 12 mini", boards: ["D52gAP"], cpuModel: "t8108"),
        "iPhone13,2": .init(name: "iPhone 12", boards: ["D53gAP"], cpuModel: "t8108"),
        "iPhone13,3": .init(name: "iPhone 12 Pro", boards: ["D53pAP"], cpuModel: "t8108"),
        "iPhone13,4": .init(name: "iPhone 12 Pro Max", boards: ["D54pAP"], cpuModel: "t8108"),
        "iPhone14,2": .init(name: "iPhone 13 Pro", boards: ["D63AP"], cpuModel: "t8110"),
        "iPhone14,3": .init(name: "iPhone 13 Pro Max", boards: ["D64AP"], cpuModel: "t8110"),
        "iPhone14,4": .init(name: "iPhone 13 mini", boards: ["D16AP"], cpuModel: "t8110"),
        "iPhone14,5": .init(name: "iPhone 13", boards: ["D17AP"], cpuModel: "t8110"),
        "iPhone14,6": .init(name: "iPhone SE (3rd generation)", boards: ["D49AP"], cpuModel: "t8110"),
        "iPhone14,7": .init(name: "iPhone 14", boards: ["D27AP"], cpuModel: "t8110"),
        "iPhone14,8": .init(name: "iPhone 14 Plus", boards: ["D28AP"], cpuModel: "t8110"),
        "iPhone15,2": .init(name: "iPhone 14 Pro", boards: ["D73AP"], cpuModel: "t8120"),
        "iPhone15,3": .init(name: "iPhone 14 Pro Max", boards: ["D74AP"], cpuModel: "t8120"),
        "iPhone15,4": .init(name: "iPhone 15", boards: ["D37AP"], cpuModel: "t8120"),
        "iPhone15,5": .init(name: "iPhone 15 Plus", boards: ["D38AP"], cpuModel: "t8120"),
        "iPhone16,1": .init(name: "iPhone 15 Pro", boards: ["D83AP"], cpuModel: "t8130"),
        "iPhone16,2": .init(name: "iPhone 15 Pro Max", boards: ["D84AP"], cpuModel: "t8130"),
        "iPhone17,1": .init(name: "iPhone 16 Pro", boards: ["D93AP"], cpuModel: "t8140"),
        "iPhone17,2": .init(name: "iPhone 16 Pro Max", boards: ["D94AP"], cpuModel: "t8140"),
        "iPhone17,3": .init(name: "iPhone 16", boards: ["D47AP"], cpuModel: "t8140a"),
        "iPhone17,4": .init(name: "iPhone 16 Plus", boards: ["D48AP"], cpuModel: "t8140a"),
        "iPhone17,5": .init(name: "iPhone 16e", boards: ["V59AP"], cpuModel: "t8140a"),
        "iPhone18,1": .init(name: "iPhone 17 Pro", boards: ["V53AP"], cpuModel: nil),
        "iPhone18,2": .init(name: "iPhone 17 Pro Max", boards: ["V54AP"], cpuModel: nil),
        "iPhone18,3": .init(name: "iPhone 17", boards: ["V57AP"], cpuModel: nil),
        "iPhone18,4": .init(name: "iPhone Air", boards: ["D23AP"], cpuModel: nil),
        "iPhone18,5": .init(name: "iPhone 17e", boards: ["V159AP"], cpuModel: nil),
        "iPhone19,2": .init(name: "iPhone 18 Pro", boards: ["V63AP"], cpuModel: nil),
        "iPhone19,3": .init(name: "iPhone 18 Pro Max", boards: ["V64AP"], cpuModel: nil),
        "iPhone19,4": .init(name: "iPhone Duo", boards: ["V68AP"], cpuModel: nil),
        "iPhone19,7": .init(name: "iPhone 18 Pro Max (Global)", boards: ["V64sAP"], cpuModel: nil),
        "iPhone99,11": .init(name: "virtual machine for iPhone Research Environment", boards: ["VPHONE600AP"], cpuModel: nil),
    ]

}
