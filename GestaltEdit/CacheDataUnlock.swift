import Foundation

/// The Siri AI eligibility gate lives in three binary booleans INSIDE the
/// CacheData blob — not (only) in CacheExtra. CacheExtra capability flags
/// alone are ignored and later scrubbed by iOS when the CacheData gate is
/// closed, which is exactly the "keys vanish, nothing activates" failure.
///
/// Offsets and target values ported from H4CNPE/YumEdit (GPL-3.0):
/// 0x720 → 1, 0xBF0 → 0, 0xFC8 → 1 (community mapping: generative-model
/// capability → 1, China-restriction flag → 0, non-China flag → 1).
///
/// Each target byte must currently be 0 or 1 with the following seven bytes
/// zero — these are aligned boolean cells in the binary cache. Anything else
/// means an unknown CacheData layout, and patching it is refused rather than
/// guessed.
enum CacheDataUnlock {
    static let bitTargets: [(offset: Int, value: UInt8)] = [(0x720, 1), (0xBF0, 0), (0xFC8, 1)]

    /// True when every target cell already holds its unlocked value.
    static func bitsReady(_ data: Data) -> Bool {
        bitTargets.allSatisfy { target in
            data.count >= target.offset + 8
                && data[target.offset] == target.value
                && data[(target.offset + 1)..<(target.offset + 8)].allSatisfy { $0 == 0 }
        }
    }

    /// Returns a copy of `data` with the three eligibility cells set. Throws
    /// when the layout does not look like the known boolean-cell pattern.
    static func patch(_ data: Data) throws -> Data {
        var bytes = data
        for target in bitTargets {
            guard bytes.count >= target.offset + 8,
                  bytes[target.offset] == 0 || bytes[target.offset] == 1,
                  bytes[(target.offset + 1)..<(target.offset + 8)].allSatisfy({ $0 == 0 }) else {
                throw SiriAIUnlockError.unknownCacheDataLayout
            }
            bytes[target.offset] = target.value
        }
        return bytes
    }
}

enum SiriAIUnlockError: LocalizedError {
    case unknownCacheDataLayout
    case machineUnknown
    case identitySpoofed
    case identityMismatch
    case regionInconsistent
    case alreadyComplete
    case unknownBorrowProfile
    case cacheDataMissing
    case notBorrowed
    case noTrustedBackup

    var errorDescription: String? {
        switch self {
        case .unknownCacheDataLayout:
            String(localized: "The CacheData blob does not match the known boolean-cell layout, so the AI eligibility bits were not patched. Nothing was changed.")
        case .machineUnknown:
            String(localized: "This device is not in the verified hardware table, so the two-stage unlock refuses to write.")
        case .identitySpoofed:
            String(localized: "The cache still carries a spoofed device identity. Restore it first: Restore tab → Device Doctor → Fix Detected Errors, restart, then run Stage 1.")
        case .identityMismatch:
            String(localized: "The cached hardware identity does not match this physical device. Repair it with Device Doctor before running Stage 1.")
        case .regionInconsistent:
            String(localized: "The stored sales region is inconsistent (region code and suffix do not match), so the unlock refuses to write.")
        case .alreadyComplete:
            String(localized: "The capability writes are already in place — nothing to change.")
        case .unknownBorrowProfile:
            String(localized: "Unknown borrow target.")
        case .cacheDataMissing:
            String(localized: "MobileGestalt is missing CacheData, so the eligibility bits cannot be patched.")
        case .notBorrowed:
            String(localized: "Stage 2 needs an active ProductType borrow. Run Stage 1 with the borrow enabled first.")
        case .noTrustedBackup:
            String(localized: "No trusted same-CacheUUID backup with this device's real identity was found, so Stage 2 refuses to write. Keep the automatic backups and try again.")
        }
    }
}
