import Foundation

/// OS Eligibility override for the Apple Intelligence feature domains,
/// written to /var/db/eligibilityd/eligibility.plist. This is the layer the
/// classic AI Enablers (Nugget, credit sneakyf1shy) used: unlike
/// MobileGestalt, these overrides flip the inputs eligibilityd evaluates
/// DIRECTLY — including OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM, the
/// exact capability A16 devices lack — so the feature gate can be satisfied
/// even where the MobileGestalt keys get scrubbed.
///
/// Structure ported from Nugget's AI Enabler (GPL-3.0):
/// - GREYMATTER (Apple Intelligence core): answer PENDING_ASSET with every
///   relevant input DEFINITELY_SATISFIED, plus the eligible-device-language
///   context — this is what drives asset provisioning and feature execution.
/// - CALCIUM: answer ELIGIBLE with the China-cellular input satisfied.
///
/// ios_eligibility enums (OSDeveloperTools headers):
/// answer source 1 = override; answers: 2 = eligible, 4 = pending asset;
/// input status 2 = satisfied, 3 = definitely satisfied.
enum AIEligibilityOverride {
    static let greyMatterDomain = "OS_ELIGIBILITY_DOMAIN_GREYMATTER"
    static let calciumDomain = "OS_ELIGIBILITY_DOMAIN_CALCIUM"

    static func overridePlist(languageCodes: [String]) -> [String: Any] {
        let langs = ["en"] + languageCodes
        return [
            calciumDomain: [
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 2,
                "status": [
                    "OS_ELIGIBILITY_INPUT_CHINA_CELLULAR": 2,
                ],
            ],
            greyMatterDomain: [
                "context": [
                    "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES": langs,
                ],
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 4,
                "status": [
                    "OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE": 3,
                    "OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE": 3,
                    "OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE": 3,
                    "OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM": 3,
                    "OS_ELIGIBILITY_INPUT_SHARED_IPAD": 3,
                    "OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE": 3,
                ],
            ],
        ]
    }

    /// True when both domains are present with an override source — i.e. the
    /// file was written by us (or Nugget) and not by the system.
    static func isApplied(_ plist: [String: Any]) -> Bool {
        let grey = plist[greyMatterDomain] as? [String: Any]
        let calcium = plist[calciumDomain] as? [String: Any]
        return (grey?["os_eligibility_answer_source_t"] as? Int) == 1
            && (grey?["os_eligibility_answer_t"] as? Int) == 4
            && (calcium?["os_eligibility_answer_source_t"] as? Int) == 1
    }

    /// Merges the override into an existing eligibility plist (other domains
    /// the system or other tools wrote are preserved), or returns the fresh
    /// override plist when there is nothing to merge with.
    static func merged(into existing: [String: Any]?, languageCodes: [String]) -> [String: Any] {
        guard var merged = existing, isStructuredPlist(merged) else {
            return overridePlist(languageCodes: languageCodes)
        }
        let override = overridePlist(languageCodes: languageCodes)
        for (domain, value) in override {
            merged[domain] = value
        }
        return merged
    }

    private static func isStructuredPlist(_ plist: [String: Any]) -> Bool {
        // A stock eligibility.plist carries OS_ELIGIBILITY_DOMAIN_* keys; a
        // foreign or corrupt file is replaced rather than merged into.
        plist.keys.contains { $0.hasPrefix("OS_ELIGIBILITY_DOMAIN_") }
    }
}

/// Persists the pre-apply eligibility.plist so the override is revertible
/// even though eligibility backups live outside the MobileGestalt backup
/// store (a different file, potentially absent on stock devices).
enum EligibilityBackupStore {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EligibilityBackups", isDirectory: true)
    }
    static var originalURL: URL {
        directory.appendingPathComponent("eligibility-original.plist")
    }
    static var absentMarkerURL: URL {
        directory.appendingPathComponent("eligibility-was-absent")
    }

    /// Saves the pre-apply state: the raw plist bytes when the file existed,
    /// an absence marker when it did not.
    static func save(original data: Data?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: absentMarkerURL)
        if let data {
            try data.write(to: originalURL, options: .atomic)
        } else {
            FileManager.default.createFile(atPath: absentMarkerURL.path, contents: nil)
        }
    }

    static func hasBackup() -> Bool {
        FileManager.default.fileExists(atPath: originalURL.path)
            || FileManager.default.fileExists(atPath: absentMarkerURL.path)
    }

    /// The original plist bytes, or nil when the file was absent. nil is also
    /// returned when no backup exists — callers distinguish via wasAbsent().
    static func load() throws -> Data? {
        if FileManager.default.fileExists(atPath: originalURL.path) {
            return try Data(contentsOf: originalURL)
        }
        if FileManager.default.fileExists(atPath: absentMarkerURL.path) { return nil }
        return nil
    }

    static func wasAbsent() -> Bool {
        FileManager.default.fileExists(atPath: absentMarkerURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: absentMarkerURL)
    }
}
