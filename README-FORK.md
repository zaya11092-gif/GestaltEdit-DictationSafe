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

## AI Feature Eligibility override (GreyMatter + 35-domain template) — v3.0.0

Apple Intelligence feature *execution* is gated by a second layer entirely
independent of MobileGestalt: the OS Eligibility Service. Its override file
lives at `/var/db/eligibilityd/eligibility.plist`, and the classic AI
Enablers (Nugget — structure credit sneakyf1shy) flipped the `GREYMATTER`
(Apple Intelligence) and `CALCIUM` domains there: answer source = override,
Apple Intelligence answer = pending-asset, and every evaluated input —
including `OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM`, the exact
capability A16 devices fail — marked definitely-satisfied.

Tools → Siri AI Unlock → **AI Feature Eligibility** writes that override
(same worse_query lease, different target directory), merged into any
existing domains, with the pre-apply file backed up automatically and
restorable in one tap. Restart after writing, then test Writing Tools, the
ChatGPT extension, the AI settings page and dictation.

**On-device result (iPhone 15 · iOS 27.2.1, 2026-11-21): REJECTED.** The
worse_query lease cannot target `/var/db/eligibilityd` — containermanagerd
answers only for systemgroup container paths and rejects the query with
code -6 ("no token") regardless of flags. The eligibility layer is
therefore unreachable with the current exploit class on this build; the
override stays in the app (kept for future exploit classes / builds), and
the failure surfaces cleanly instead of half-applying. Nugget's own iOS
**On-device result (iPhone 15 · iOS 27.2.1, 2026-11-21): /var/db REJECTED —
container target discovered.** The worse_query lease cannot target
`/var/db/eligibilityd` — containermanagerd answers only for systemgroup
container paths and rejects the query with code -6 ("no token").
`systemgroup.com.apple.oseligibilityservice` IS a real systemgroup
container (confirmed by system logs), i.e. the exact path class the
MobileGestalt lease provably works on. v3.0.0 therefore probes BOTH
targets, lists the container's files on device, and writes the merged
override (35-region-domain US template + GREYMATTER/CALCIUM AI overlay)
into every reachable one — with per-target backups and one-tap revert.
Whether eligibilityd honors a container-side eligibility.plist on 27.2.1
is the experiment the probe + write answers.

26.2+ caveat (backup-restore vector unsupported) points the same
direction: Apple moved AI eligibility past client-side files.

The UI otherwise mirrors the original app: **Enable Siri AI toggle +
Activation Mode picker** (Capabilities only — the dictation-safe analogue;
Borrow identity for download), staged through the global Apply button,
followed by Finish · Restore Real Identity once the resources are
downloaded. The revert always restores the backed-up original (or removes
the file when it did not exist before).

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
- **The v2.9.0 experimental capability keys hang Siri provisioning**:
  writing DeviceSupportsGrey + generative-model-systems + the on-device Siri
  capability family left the device stuck on a looping "Updating Siri"
  provisioning state that survived restarts and re-spoofs. Recovery:
  Device Doctor → Fix Detected Errors → Remove Siri AI Activation Keys →
  full restart, escalating to Factory Cache Reset and then a device restore.
  Conclusion: the expanded Siri provisioning stack does not refuse an A16 —
  it hangs, which is a harder wall than ineligibility.
- **Dictation recovery ladder** (in order): remove the AI keys + close the
  gate → restart → per-language refresh (remove language → restart → re-add
  on Wi-Fi) → Factory Cache Reset → restart → re-add languages. If dictation
  is still broken after a factory cache reset, the damage is outside
  MobileGestalt entirely and the guaranteed fix is a full device restore
  (DFU/Finder with the stock IPSW).

**v3.0.0 container result (iPhone 15 · iOS 27.2.1, 2026-11-22): the
eligibility layer is reachable — and it hangs too.** The
oseligibilityservice systemgroup container lease succeeds, the 37-domain
override (35 region domains + GREYMATTER/CALCIUM) writes and verifies, and
the provisioning stack engages — then hangs on a looping "Siri is
updating" that survives restarts. With this, all three plist layers are
tested on A16 and all three produce the same end state: surface yes,
generative execution no, speech stack wedged while the forced state is
active. Recovery: Restore Original Eligibility + Remove Siri AI Activation
Keys → restart; escalate to Factory Cache Reset, then a device restore.

**Correction (2026-11-23):** earlier revisions of this file stated the
wall was "the on-device runtime (RAM/model requirements)". That was never
established. Public reports from the iOS 18.1 era describe Writing Tools
and other features running on older, lower-RAM phones after the same kind
of enable, so the A16 is not shown to be incapable. The cause of the
hang on iOS 27.2.1 is undiagnosed: no device logs have been captured
during the stuck state, and no source documents how the generative-model
asset catalog decides what to serve.

**Classic single-key result (v3.1.0, iPhone 15 · iOS 27.2.1):** enabling
only `DeviceSupportsGenerativeModelSystems = 1` also ended in Siri stuck on
"Downloading". The same stuck-download symptom is publicly reported for
the iOS 18.1 enable guides, so it is not specific to the expanded-Siri
writes. Five configurations have now been tried on this device and every
one that starts AI provisioning ends stuck or with non-working features.

Conclusion for A16 devices on iOS 27.2.1: no configuration tried so far
produces working generative features. The block sits beyond the files this
exploit class can write; whether it is the asset catalog, eligibility, or
a local provisioning fault is not yet known. On A17 Pro-class hardware and
above the calculus may differ; the mechanism itself (gate patching,
two-stage flow, verified saves) is tested in CI only.

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

## Downloaded Siri AI Model management (Device Doctor) — v3.2.0

Restore tab → Device Doctor → **Downloaded Siri AI Models**: probes the
known on-device model asset stores (the `UAF_FM_GenerativeModels`
MobileAsset namespace, its SiriSummarization sibling, and the
mobileasset.autoassets systemgroup container) and reports per target
whether the lease reaches it and how many `.asset` bundles are present.
Targets reported ✗ are plain system paths this exploit class cannot lease
on the current build.

**Hide Downloaded Models is DISABLED as of v3.2.1.** It was shipped in
v3.2.0 described as forcing a fresh download; that was never verified and
the description was wrong. The `.asset` bundles live in `purpose_auto/`
subfolders, which the probe does not enter, so on that layout the button
renamed nothing. On a layout with bundles at the namespace root it would
rename them behind the asset system's back. After it was used on an iPhone
15 / iOS 27.2.1, Siri stayed stuck on "Downloading"; whether the button
caused that is not known. **Restore Hidden Models** remains available as
the undo for anything it did rename. To clear downloaded models for a
real redownload, use Settings → General → Transfer or Reset iPhone →
Reset All Settings (resets system settings and removes Apple Pay cards;
keeps data) or a device restore.
