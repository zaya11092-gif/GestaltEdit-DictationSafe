# GestaltEdit — Dictation-Safe Fork (v2.7.0)

A fork of [frs0n/GestaltEdit](https://github.com/frs0n/GestaltEdit) (GPL-3.0) rebuilt
around the **YumEdit two-stage Siri AI unlock** — the approach that has made the most
real progress toward full Siri AI on devices Apple does not support, including the
iPhone 15 / 15 Plus (A16).

**v2.7.0 replaces the fork's previous activation system entirely** (dictation-safe /
temporary spoof / AI Expansion are gone). Ported from
[H4CNPE/YumEdit](https://github.com/H4CNPE/YumEdit) (GPL-3.0); credit where due — the
CacheData gate offsets, the minimal borrow concept and the never-open-Siri rule are
YumEdit's findings.

## What was wrong with every previous approach

To enable Siri AI on unsupported devices, this fork (and upstream) wrote
**CacheExtra capability flags** (`DeviceSupportsGenerativeModelSystems`, SiriMode,
invented "persistence triple" keys) with or without a full hardware-identity borrow.
On-device testing on iOS 27.2.1 showed the real behavior:

- The **eligibility gate lives in three binary booleans INSIDE the CacheData blob**
  (`0x720 → 1`, `0xBF0 → 0`, `0xFC8 → 1` — YumEdit's community mapping: generative
  capability, China-restriction, non-China). With the gate closed, iOS ignores the
  CacheExtra flags and **scrubs them** — which is why activations "succeeded",
  resources briefly downloaded, and then the whole feature surface vanished with the
  keys gone while the borrowed identity stayed.
- The invented iOS 27 persistence keys are not part of the real unlock.
- Opening **Settings → Siri** after the identity revert re-runs eligibility against
  the real hardware and can invalidate the downloaded resources — YumEdit's
  documented failure mode, and the reason earlier attempts here kept dying.

## The v2.7.0 unlock (two stages, YumEdit method)

### Stage 1 — capabilities + gate (+ optional borrow)

One verified save writes:

| Write | Value |
|---|---|
| Sales region | `LL` / `LL/A` (US region — part of the unlock) |
| `a3n5T9sFtlyQ74NEp9ESxg` (SiriMode) | `2` |
| `A62OafQ85EJAiiqKn4agtg` (generative capability) | `1` |
| **CacheData eligibility gate** | three booleans patched in place (unknown layouts refused) |
| *(optional)* ProductType borrow | an eligible ProductType — **ProductType only** |

The borrow is optional and deliberately minimal: board, CPU, thinning type and the
regulatory model **stay physical**, so Face ID and dictation damage is minimal and
the revert is trivial. Try Stage 1 without the borrow first; enable it if resources
refuse to download.

**Then: full restart.** After the restart, set the Siri language to
a language that MATCHES the iPhone language (iOS requires both to be the same supported Apple Intelligence language) and let the Apple resources download over Wi-Fi,
uninterrupted. Do not run fixes, do not restore anything while this runs.

### Stage 2 — restore the real identity, keep everything that matters

Only after the download has finished: the app selects the **trusted backup** (same
`CacheUUID`, CacheData provenance proven, ProductType/board/CPU = the physical
device) and restores the complete identity while **keeping** the US region, SiriMode
2, the capability flag and the open CacheData gate. Full restart.

Face ID and dictation come back with the real identity; the capability surface stays.

### The one rule that decides everything

**After Stage 2, NEVER open Settings → Siri (or Apple Intelligence & Siri).**
That page re-runs device eligibility against the real hardware and can invalidate
the downloaded resources and strip the capability keys. **Test Siri by voice only**
(side button / voice trigger). If a dictation language is wedged, remove it from
Settings → General → Keyboard → Dictation Languages, restart, and re-add it on Wi-Fi.

## Device Doctor (updated)

Restore tab → Device Doctor → Scan Device Identity now understands the two-stage
states and reports the **CacheData gate state** in every report:

- **STAGE 1 BORROW ACTIVE** — borrow + capability keys + open gate: expected
  mid-unlock, do not repair, finish the download and run Stage 2.
- **SIRI AI UNLOCK ACTIVE** — real identity restored, capability keys + open gate
  intentionally present: these keys are NOT damage; do not remove them.
- **DEVICE IDENTITY SPOOFED** — identity damage (from any editor): Fix Detected
  Errors restores the identity from kernel/IOKit/verified backups.
- **Keys-only residue** — capability keys present but the CacheData gate closed:
  a stripped or never-completed unlock. Fix removes the keys and restores the
  pre-unlock CacheData from the same-CacheUUID backup.

## Dictation & Face ID Repair

Restore tab → any verified backup → **Repair Dictation & Face ID** — unchanged from
v2.6: restores the complete hardware identity (10 identity keys, kernel-validated
backup source) while keeping AI flags, SiriMode, region settings and unrelated
edits. Works against damage from this fork, upstream, GestaltX, Gester, Nugget or
any other editor.

## On-device verification results (iPhone 15 · iOS 27.2.1 · 2026-11)

Real-device results from the exact device class this fork targets, after the
complete two-stage flow (borrow → 100% model download → identity revert →
gate re-open attempts):

- The unlock **mechanism works**: capability keys + CacheData gate persist,
  the new Siri settings surface appears, and the model download completes.
- The **iOS 27 new Siri runtime does not engage on A16**: even with models
  downloaded, the gate open, and the identity restored, the device keeps the
  old (iOS 18–26) Apple Intelligence stack. The gate was also observed
  closed again after restarts (boot-time CacheData rebuild).
- Surfacing the old stack **does not make it functional**: Writing Tools and
  the ChatGPT extension do not work, and the forced generative pipeline
  wedges dictation and spoken Siri across ALL languages (US/UK/AU/NZ).
- **Dictation recovery ladder** (in order): remove the AI keys + close the
  gate → restart → per-language refresh (remove language → restart → re-add
  on Wi-Fi) → Factory Cache Reset → restart → re-add languages. If dictation
  is still broken after a factory cache reset, the damage is outside
  MobileGestalt entirely and the guaranteed fix is a full device restore
  (DFU/Finder with the stock IPSW).

Conclusion for A16 devices on iOS 27.2.1: the achievable surface via
MobileGestalt is the old Apple Intelligence UI with non-functional
generative features, at the cost of working dictation. The new Siri runtime
is gated beyond what a plist edit can reach (on-device runtime requirements
plus server-side model provisioning keyed to the device). On A17 Pro-class
hardware and above the calculus may differ; the mechanism itself (gate
patching, two-stage flow, verified saves) is sound and fully tested.

## Honest limits

- YumEdit itself labels the older-device path experimental; the CH/A region
  conversion is its proven core. Expect iteration.
- Server-side availability still depends on Apple: an EU or China-mainland Apple
  Account can keep the feature surface away with every key set. No client edit can
  force that.
- The A16 sits below Apple's official A17 Pro bar: expect the new Siri to be
  slower, and some features may never run.
- Whether Image Playground and the dedicated Siri app survive Stage 2 on the real
  hardware is exactly what this rebuild is meant to find out — keep backups.

## How to use (short form)

1. Sign the IPA (iLoader/isideload — an App Group entitlement is required), open the
   app, confirm the device reads successfully.
2. Tools → Siri AI Unlock → **Stage 1** (borrow optional) → **full restart**.
3. Siri language → set it to MATCH the iPhone language (e.g. English (United States) on a US device) → let resources download on Wi-Fi.
4. Tools → Siri AI Unlock → confirm download finished → **Stage 2** → **full restart**.
5. Test Siri **by voice only**. Never open the Siri settings page. Check Face ID and
   dictation; refresh wedged languages on Wi-Fi.
6. Anything broken: Restore → Device Doctor → Scan → Fix Detected Errors.

## Files changed vs upstream

- `GestaltEdit/CacheDataUnlock.swift` (new) — CacheData eligibility-bit patch/verify
  (YumEdit offsets, layout-validated, idempotent).
- `GestaltEdit/GestaltModels.swift` — `SiriAIYumUnlock` (state machine, Stage 1 /
  Stage 2, trusted-backup provenance via CacheUUID + CacheData, pre-unlock CacheData
  recovery). The old `AIRegionConfiguration` and its invented persistence keys are
  removed.
- `GestaltEdit/GestaltViewModel.swift` — two-stage flows through the verified save
  path (auto-backup, read-back verification of capabilities, gate and identity),
  CacheData restoration on explicit AI revert.
- `GestaltEdit/DeviceIdentityAudit.swift` — CacheData gate reporting, stage-1 /
  stage-2 verdicts, hardware-truth helpers (`expectedBoard`/`expectedCPU`).
- `GestaltEdit/ContentView.swift` — Tools → Region: two-stage unlock UI with live
  state rows; Fix-sheet defaults never pre-enable key removal during an active
  unlock. The old activation-mode picker and setup guide are gone.
- `.github/workflows/*` — logic tests gate the IPA build; the embedded Watch helper
  is stripped from the IPA (static `WKCompanionAppBundleIdentifier` cannot match
  bundle-ID-rewriting signers; upstream frs0n/GestaltEdit#108).
- `Tests/GestaltPresets/main.swift` — full coverage for the CacheData gate, Stage 1
  / Stage 2, trusted-backup provenance and the new doctor verdicts.

## Building

Same as upstream: `xcodebuild archive -project GestaltEdit.xcodeproj -scheme
GestaltEdit -configuration Release -destination 'generic/platform=iOS'
CODE_SIGN_IDENTITY="" ...` or use the repo's GitHub Action (tests run first and gate
the build). Requires iOS / iPadOS 27+ and Developer Mode; a signing tool that
preserves an App Group entitlement.

## Running the logic tests

```
xcrun swiftc GestaltEdit/GestaltModels.swift GestaltEdit/CacheDataUnlock.swift \
  GestaltEdit/DeviceIdentityAudit.swift GestaltEdit/GestaltTweaks.swift \
  GestaltEdit/GestaltBackupStore.swift Tests/GestaltPresets/main.swift \
  -o /tmp/gestalt-preset-tests && /tmp/gestalt-preset-tests
```

## License

GPL-3.0, same as upstream. Based on GestaltEdit by frs0n; the two-stage unlock ports
mechanism and offsets from H4CNPE/YumEdit (GPL-3.0); the on-device write path is the
forcequitOS/worse_query PoC (GPL-3.0). Upstream's app uses private APIs and modifies
system caches — use at your own risk; bad MobileGestalt values can break features or
require restoring the device.
