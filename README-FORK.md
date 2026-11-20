# GestaltEdit — Dictation-Safe Fork

A fork of [frs0n/GestaltEdit](https://github.com/frs0n/GestaltEdit) (GPL-3.0) with a
**dictation-safe Siri AI activation** that fixes the "dictation and spoken Siri stop
working after enabling Siri AI" bug on unsupported iOS 27 devices.

## What was wrong

To enable Siri AI on unsupported devices, upstream GestaltEdit always wrote a temporary
**hardware identity spoof** into the MobileGestalt cache during setup
(`ProductType → iPhone16,1`, `HardwareModel → D83AP`, `CPUModel → t8130`, and for
mainland-China region conversions also the regulatory model number). While that spoof is
in the cache, the speech stack (dictation, the "Hey Siri" voice trigger, and Siri's own
speech recognition) and Face ID select/validate hardware-specific resources against a
device that does not exist, so **Face ID and dictation stop working until the spoof is
removed** (this is documented in upstream's own setup warning). Upstream leaves the spoof
in place until the user manually runs "After Model Download · Remove Device Spoof" — and
if that step is missed, or the identity was damaged by another editor (GestaltX ≤ 1.0.5,
Gester, manual edits), dictation stays broken.

## What this fork changes

### 1. Dictation-safe activation (new default)

"Enable Siri AI" on unsupported devices now writes **only the software capability flags**
and never touches device identity:

| Key | Meaning | Dictation-safe write |
|---|---|---|
| `A62OafQ85EJAiiqKn4agtg` | DeviceSupportsGenerativeModelSystems | `1` |
| `a3n5T9sFtlyQ74NEp9ESxg` | SiriMode | `2` |
| `h63QSdBCiT/z0WU6rdQv6Q` / `yK+xavymRGZ3xWc1tb8XDg` / `zHeENZu+wbg7PUprwNwBWg` | Region code / suffixes | rewritten **only** for mainland-CH devices (upstream logic kept), regulatory model number **not** rewritten |
| `h9jDsbgj7xIVeIQ8S3/X3Q` (ProductType), `oYicEKzVTz4/CxxE05pEgQ` (HardwareModel), `5pYKlGnYYBzGvAlIU8RjEQ` (CPUModel), `97JDvERpVwO+GHtthIh7hA` (ModelNumber), `K/R1GfGfCkXvEhaPS2Vrng` (on-device Siri capability) | **Never written** | unchanged |

A new **Activation Mode** picker appears in Tools → Region for unsupported devices:

- **Dictation Safe** (default) — capability flags only; Face ID, dictation and spoken
  Siri are never affected because identity is never modified.
- **Temporary Spoof (fallback)** — upstream's two-stage behavior, for when Settings
  refuses to download the Siri AI models on an unspoofed device. Spoof → download models
  → Restore → "After Model Download · Remove Device Spoof" → restart. The warning dialog
  now reflects the selected mode.

Every dictation-safe write is verified: after writing, the app re-reads the plist and
fails the operation if any identity key or the on-device Siri capability changed.

### 2. Device Doctor — scan the MobileGestalt cache and fix the damage

Restore tab → **Device Doctor → Scan Device Identity**. This tool answers "why is
dictation broken?" with or without a backup, and repairs what it finds:

- **Scans** every identity key in the cache — ProductType, ThinningProductType,
  GSDeviceName, HardwareModel (TargetSubType), HWModelStr, HardwarePlatform
  (CPUModel), RegulatoryModelNumber, the on-device Siri understanding flag and
  the marketing-name keys — against what the hardware itself reports:
  `hw.machine` (kernel), `hw.model` (board string), the IOKit device tree
  (`platform-name`, the real SoC code) and a built-in device database
  (identifiers, boards and CPU codes for iPhone 11-era through iPhone 18 and
  iPad M1–M3). A verdict is produced in seconds; the report is shareable as text.
- **Scans for Siri AI residue**: leftover activation keys
  (`A62OafQ85EJAiiqKn4agtg` capability flag, `a3n5T9sFtlyQ74NEp9ESxg` SiriMode)
  and the LL/LL/A region override that editors write. **This is the leading
  cause of "Identity Matches This Device but dictation is still broken"** —
  with a clean identity, these keys keep the Siri stack running the generative
  pipeline the device cannot complete, which wedges dictation and spoken Siri.
- **Full cache inventory**: the shareable report lists *every* stored key and
  value, so nothing an editor wrote can hide outside the audited key set.
- **Fixes** detected problems with a fully reviewed write plan: identity spoofs
  are restored from kernel/IOKit/verified backup/device database (never
  guessed), and optional toggles remove the Siri AI activation keys (on by
  default when residue is found — reversible, Siri AI can be re-enabled later),
  the LL region override, and the on-device Siri understanding flag. The
  current file is backed up automatically before writing and every value is
  re-verified after writing.
- **Guided triage** when everything is clean: Enable Dictation toggle,
  dictation languages, Screen Time restrictions, Siri & Search, full restart.
- **Factory Cache Reset** (last resort, confirm-to-run): backs up the current
  file, wipes every cached answer, and lets iOS rebuild a brand-new native
  cache on the next restart. Removes all MobileGestalt edits — the guaranteed
  cure when the cache itself is damaged but no single audited key explains it.

### 3. Dictation & Face ID Repair (new Restore action)

Restore tab → any standard backup → **"Repair Dictation & Face ID"**. This is the
recovery path if dictation, spoken Siri or Face ID are already broken after a device
spoof from *any* editor:

- Restores the complete hardware identity from the chosen original backup:
  ProductType, HardwareModel, CPUModel **and the regulatory model number** (upstream's
  "Remove Device Spoof" restores only the first three), plus the device-specific
  **on-device Siri capability** `K/R1GfGfCkXvEhaPS2Vrng` (removed if it was absent
  originally — an overwritten value breaks the Apple Intelligence Siri interface).
- Keeps everything else: Apple Intelligence capability, SiriMode 2, region settings,
  downloaded-model eligibility and unrelated edits.
- Validates the repair source before writing: the backup's ProductType (and
  ThinningProductType) must match the physical device reported by the kernel
  (`hw.machine`, board-suffix tolerant). Backups taken while a spoof was
  active, foreign-device backups and incomplete identities are rejected
  instead of guessed. The current plist is backed up automatically before the
  write, and the result is verified after it. Crucially, a still-spoofed live
  cache never disqualifies a clean backup — that comparison was a false
  rejection in early versions.
- Restart the device after a successful repair, then test Face ID, dictation and Siri.

## How to use

1. Build and install (see below). Open the app, confirm the device reads successfully.
2. Tools → Region → **Enable Siri AI**. Keep **Activation Mode: Dictation Safe**, Apply.
3. Settings → Siri: the new Siri interface / Siri AI settings appear; download models.
4. If model download is blocked: switch Activation Mode to **Temporary Spoof**, Apply,
   download the models, then Restore → "After Model Download · Remove Device Spoof" and
   restart. Face ID and dictation return; Siri AI settings stay enabled.
5. If dictation/Siri/Face ID are already broken (from any editor): Restore →
   Device Doctor → **Scan Device Identity**:
   - **Device Spoof Detected** → **Fix Detected Errors** → restart.
   - **Identity OK — Siri AI Keys in Cache** → **Fix Detected Errors** (the
     "Remove Siri AI Activation Keys" toggle is on by default) → restart.
     Re-enable Siri AI afterwards from the Siri AI tab if you want it back.
   - **Identity Matches This Device** (fully clean) → follow the in-app triage
     checklist; only as the last resort use **Factory Cache Reset** → restart.
   - Or: Restore → pick the oldest/original backup → **Repair Dictation & Face
     ID** → restart.

Honest caveats: server-side availability of Siri AI still depends on Apple's services and
region (no client edit can guarantee it); dictation-safe activation may not pass every
model-download eligibility check, in which case use the fallback mode. Editing
MobileGestalt always carries risk — keep backups.

## Files changed vs upstream

- `GestaltEdit/GestaltModels.swift` — `SiriAIActivationMode`, mode-aware
  `AIRegionConfiguration` (capability-only writes, regulatory-model guard),
  extended `DictationRepairRestore` (10 identity keys, kernel identity check
  covering ThinningProductType), `GestaltPlist.clearCacheExtra()`.
- `GestaltEdit/DeviceIdentityAudit.swift` — the Device Doctor: cache-vs-hardware
  audit, Siri AI residue scan (activation keys + region override), full cache
  inventory, shareable reports, verified fix plans, built-in device database.
- `GestaltEdit/IdentityProbe.swift` + `GestaltAccess.h/.m` — IOKit device-tree
  probe (`platform-name`) and `hw.model` sysctl wrapper.
- `GestaltEdit/GestaltViewModel.swift` — activation-mode state and warnings,
  mode-aware apply, hardened save verification (identity-preservation check),
  `repairDictation(from:)` that no longer false-rejects clean backups while the
  live cache is spoofed, Device Doctor scan/fix flows, new error case.
- `GestaltEdit/ContentView.swift` — Activation Mode picker, mode-aware risk
  icon, Repair button in backup details, Device Doctor section, report and
  fix-review UI, fork marker in the Developer section.
- `Tests/GestaltPresets/main.swift` — spoof tests pinned to `.temporarySpoof`,
  dictation-safe, repair and Device Doctor test coverage.
- `GestaltEdit/zh-Hans.lproj/Localizable.strings` — Simplified Chinese for all
  new strings.

The new Swift files are picked up automatically by the project's
filesystem-synchronized groups — no pbxproj edits were required.

## Building

Same as upstream: open `GestaltEdit.xcodeproj` in Xcode, archive for iOS
(`xcodebuild archive -project GestaltEdit.xcodeproj -scheme GestaltEdit -configuration
Release -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" ...` produces an
unsigned IPA, or use the repo's GitHub Action), then sideload with a signing tool
(iLoader etc.). Developer Mode must be enabled. Requires iOS / iPadOS 27.

## Running the logic tests

```
xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/DeviceIdentityAudit.swift \
  GestaltEdit/GestaltTweaks.swift GestaltEdit/GestaltBackupStore.swift \
  Tests/GestaltPresets/main.swift -o /tmp/gestalt-preset-tests && /tmp/gestalt-preset-tests
```

## License

GPL-3.0, same as upstream. Based on GestaltEdit by frs0n; this fork's changes are also
GPL-3.0. Upstream's app uses private APIs and modifies system caches — use at your own
risk; bad MobileGestalt values can break features or require restoring the device.
