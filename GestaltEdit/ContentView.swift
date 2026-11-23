import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: GestaltViewModel

    var body: some View {
        Group {
            if !GestaltAccess.supportsDeviceAccess {
                ContentUnavailableView(
                    "iOS 26 Is Not Supported",
                    systemImage: "iphone.slash",
                    description: Text("On-device MobileGestalt editing requires iOS / iPadOS 27 or later. iOS / iPadOS 26 is not supported.")
                )
            } else {
                TabView {
                    TweakWorkbench()
                        .tabItem { Label("Tools", systemImage: "switch.2") }

                    NavigationStack { AdvancedGestaltEditor().id(viewModel.deviceContextID) }
                        .tabItem { Label("Fields", systemImage: "list.bullet.rectangle") }

                    BackupLibrary().id(viewModel.deviceContextID)
                        .tabItem { Label("Restore", systemImage: "archivebox") }
                }
                .disabled(viewModel.isBusy)
                .task { viewModel.load() }
            }
        }
        .overlay {
            if viewModel.isRespringing {
                NeoSpringView()
            }
        }
        .alert(item: $viewModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct TweakWorkbench: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsStageTwoConfirmation = false
    @State private var yumStageTwoConfirmed = false
    @State private var eligibilityLanguages = "en, en-US"
    @State private var cacheDataFlipOffset = ""
    @State private var cacheDataFlipValue = "1"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceSelector(watch: viewModel.watch)
                    if viewModel.plist == nil { deviceStatus }
                }

                if viewModel.selectedDevice == .appleWatch {
                    WatchToolsSections()
                        .disabled(viewModel.plist == nil)
                } else if viewModel.plist != nil {
                    tweakSection(.region)
                    dynamicIslandSection
                    tweakSection(.display)
                    tweakSection(.ipad)
                    tweakSection(.hardware)
                    tweakSection(.audio)
                    Section {
                        DisclosureGroup("Settings Shortcuts") {
                            tweakRows(.settings)
                        }
                        DisclosureGroup("Internal & Research") {
                            tweakRows(.internalFeatures)
                        }
                        DisclosureGroup("Device Name") {
                            modelNameControls
                        }
                    } header: {
                        Text("Advanced")
                    }
                }

                Section(String(localized: "Developer")) {
                    Text("Dictation-Safe Fork · Siri AI setup never spoofs device identity by default")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DeveloperFooter()

                    PlacardPromotionLink()

                    Link(destination: URL(string: "https://ko-fi.com/su_ss")!) {
                        HStack(spacing: 12) {
                            Image("KoFi")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Support the Developer")
                                Text("Ko-fi · SUSS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .frame(minHeight: 40)
                    }
                }
            }
            .navigationTitle("GestaltEdit")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { viewModel.load() }
            .safeAreaInset(edge: .bottom) {
                if viewModel.hasStagedTweaks {
                    applyBar
                }
            }
        }
    }

    private func tweakSection(_ category: GestaltTweakCategory) -> some View {
        Section(category.label) {
            if category == .ipad {
                tweakRow(.iPadOS)
                DisclosureGroup("Individual iPad Options") {
                    tweakRow(.stageManager)
                    tweakRow(.iPadApps)
                }
            } else {
                tweakRows(category)
            }
            if category == .display {
                Picker("Liquid Glass", selection: Binding<Int>(
                    get: {
                        if viewModel.selectedTweaks.contains(.enableLiquidGlassLowPerformance) { return 1 }
                        if viewModel.selectedTweaks.contains(.disableLiquidGlassLowPerformance) { return 0 }
                        return -1
                    },
                    set: { value in
                        viewModel.setTweak(.enableLiquidGlassLowPerformance, enabled: false)
                        viewModel.setTweak(.disableLiquidGlassLowPerformance, enabled: false)
                        if value >= 0 {
                            viewModel.setTweak(value == 1 ? .enableLiquidGlassLowPerformance : .disableLiquidGlassLowPerformance, enabled: true)
                        }
                    }
                )) {
                    Text("No Change").tag(-1)
                    Text("Reduced Effects").tag(1)
                    Text("Full Effects").tag(0)
                }
                DisclosureGroup("AOD Options") {
                    tweakRow(.alwaysOnDisplayVibrancy)
                    tweakRow(.aodHighLuminance)
                    tweakRow(.aodFlipbook)
                }
            }
            if category == .region {
                if viewModel.requiresForcedAIEnable {
                    siriAIUnlockControls
                }
                Picker("Device Region", selection: Binding<String?>(
                    get: { viewModel.regionPresetID },
                    set: { viewModel.setRegionPreset($0) }
                )) {
                    Text("No Change").tag(String?.none)
                    ForEach(GestaltRegionPreset.all) { region in
                        Text(region.title).tag(String?.some(region.id))
                    }
                }
            }
        }
    }

    // MARK: Siri AI two-stage unlock (YumEdit method)

    private var siriAIStatus: (text: String, color: Color) {
        guard let state = viewModel.yumState else { return ("Not read", .secondary) }
        if state.isBorrowed { return ("Setup active — borrow", .orange) }
        if state.unlockActive { return ("Active", .green) }
        if !state.identityMatchesHardware { return ("Identity damaged — scan in Restore", .red) }
        if state.capabilitiesWritten { return ("Capabilities written", .secondary) }
        return ("Not started", .secondary)
    }

    private var borrowProfileName: String {
        SiriAIYumUnlock.borrowProfiles.first(where: { $0.id == viewModel.yumBorrowProduct })?.name
            ?? viewModel.yumBorrowProduct
    }

    private func stageCacheDataFlip() {
        var clean = cacheDataFlipOffset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("0x") { clean.removeFirst(2) }
        guard let offset = Int(clean, radix: 16),
              let value = UInt8(cacheDataFlipValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value <= 1 else {
            return
        }
        viewModel.stageCacheDataBit(offset: offset, value: value)
    }

    @ViewBuilder
    private var siriAIUnlockControls: some View {
        Group {
            HStack {
                Text("Status")
                Spacer()
                Text(siriAIStatus.text).foregroundStyle(siriAIStatus.color)
            }
            .font(.subheadline)

            if viewModel.yumState?.isBorrowed == true {
                Label("Restart now, set Siri language to match the iPhone language, and let the resources download on Wi-Fi. Return only when the download has finished.", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Toggle("Resources finished downloading", isOn: $yumStageTwoConfirmed)
                Button("Finish · Restore Real Identity") {
                    showsStageTwoConfirmation = true
                }
                .disabled(!yumStageTwoConfirmed)
            } else {
                Toggle("Enable Siri AI", isOn: Binding(
                    get: { viewModel.stagesSiriAI },
                    set: { viewModel.setStagesSiriAI(enabled: $0) }
                ))
                if viewModel.stagesSiriAI {
                    Picker("Activation Mode", selection: $viewModel.siriAIStageMode) {
                        Text("Classic Apple Intelligence (iOS 18-26)").tag(SiriAIYumUnlock.StageMode.classic)
                        Text("Expanded Siri (iOS 27 - experimental)").tag(SiriAIYumUnlock.StageMode.expanded)
                    }
                    if viewModel.siriAIStageMode == .expanded {
                        Menu {
                            ForEach(SiriAIYumUnlock.borrowProfiles) { profile in
                                Button("\(profile.name) (\(profile.product))") {
                                    viewModel.yumBorrowProduct = profile.product
                                }
                            }
                        } label: {
                            HStack {
                                Text("Borrow target")
                                Spacer()
                                Text(borrowProfileName).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if viewModel.yumState?.unlockActive == true {
                Label("Active. Never open Settings → Siri — test by voice only.", systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            DisclosureGroup("Experimental AI capability keys (research)") {
                Text("iOS 27 queries these AI capability keys but stock A16 caches never store them. Toggling advertises the capability; Apply reconciles the cache; the Device Doctor residue cleanup removes them again. They can wedge the speech stack — that is the experiment.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(ExperimentalAICapabilities.keys) { capability in
                    Toggle(capability.name, isOn: Binding(
                        get: { viewModel.experimentalKeyOn(capability.key) },
                        set: { viewModel.setExperimentalKey(capability.key, on: $0) }
                    ))
                    .font(.footnote)
                }
            }
            DisclosureGroup("CacheData cells (research)") {
                Text("Live boolean cells inside CacheData. Active cells are capabilities currently switched on; suggested cells are zero siblings near active ones — likely unswitched members of the same feature family. Flip precisely: an unknown cell can wedge features until reverted (staging the opposite value undoes it).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if viewModel.cacheDataActiveCells.isEmpty {
                    Text("No active cells detected in the current CacheData.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.cacheDataActiveCells) { cell in
                    HStack {
                        Text(viewModel.cacheDataCellLabel(cell.offset)
                             ?? String(format: "cell 0x%X", cell.offset))
                        Spacer()
                        Text("on")
                            .foregroundStyle(.green)
                    }
                    .font(.footnote)
                }
                TextField("Flip cell at offset (hex, e.g. 0x830)", text: $cacheDataFlipOffset)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                TextField("New value (0 or 1)", text: $cacheDataFlipValue)
                    .font(.footnote)
                Button("Stage Cell Flip") {
                    stageCacheDataFlip()
                }
                Text("Staged flips land with the next Apply.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Feature eligibility override (advanced)") {
                Text("Writes the OS Eligibility data that decides whether AI features actually execute — independent of MobileGestalt. Two targets are probed: the oseligibilityservice systemgroup container (the same path class the MobileGestalt lease works on) and the classic /var/db/eligibilityd store. The written plist merges Nugget's 35-domain US-region eligibility template with the Apple Intelligence domains (GreyMatter: every evaluated input — including the generative-model-system input A16 devices fail — marked definitely-satisfied via override source). Languages must include the ones used for Siri and dictation. Restart after writing, then test Writing Tools, the ChatGPT extension and dictation. One-tap revert; each target's pre-apply state is backed up.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.eligibilityTargetReports, id: \.self) { report in
                    Text(report)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if viewModel.eligibilityReachableCount == 0 {
                    Text("No eligibility target is reachable with the current exploit class on this build — the override cannot be applied here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("Languages (comma separated)", text: $eligibilityLanguages)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                Button("Write Eligibility Override") {
                    viewModel.applyAIEligibilityOverride(languageText: eligibilityLanguages)
                }
                .disabled(viewModel.eligibilityReachableCount == 0)
                Button("Restore Original Eligibility") {
                    viewModel.revertAIEligibilityOverride()
                }
            }
            .onAppear { viewModel.probeAIEligibility() }
        }
        .confirmationDialog("Restore your real identity?", isPresented: $showsStageTwoConfirmation, titleVisibility: .visible) {
            Button("Restore Real Identity", role: .destructive) {
                viewModel.finishYumStageTwo()
            }
        } message: {
            Text("Restores your real identity from the trusted backup and keeps every capability write and the open gate. Restart afterwards, then NEVER open Settings → Siri — test Siri by voice only.")
        }
    }

    private func tweakRows(_ category: GestaltTweakCategory) -> some View {
        let customControls: Set<GestaltTweakID> = [
            .supportsDynamicIsland, .alwaysOnDisplayVibrancy, .aodHighLuminance, .aodFlipbook,
            .enableLiquidGlassLowPerformance, .disableLiquidGlassLowPerformance
        ]
        let definitions = GestaltTweakCatalog.definitions.filter {
            $0.category == category && !customControls.contains($0.id) && $0.isAvailable()
        }
        return ForEach(definitions) { definition in
            tweakRow(definition.id)
        }
    }

    @ViewBuilder
    private func tweakRow(_ id: GestaltTweakID) -> some View {
        if let definition = GestaltTweakCatalog.definition(for: id), definition.isAvailable() {
            let included = (viewModel.selectedTweaks.contains(.iPadOS)
                && GestaltTweakCatalog.iPadIncludedTweaks.contains(id))
            TweakToggle(
                definition: definition,
                isOn: Binding(
                    get: { included || viewModel.selectedTweaks.contains(id) },
                    set: { viewModel.setTweak(id, enabled: $0) }
                ),
                included: included
            )
        }
    }

    @ViewBuilder
    private var deviceStatus: some View {
        if viewModel.plist == nil {
            HStack(spacing: 10) {
                if viewModel.isBusy || !viewModel.hasAttemptedLoad {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading MobileGestalt…")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unable to read MobileGestalt")
                        Button("Reload", action: viewModel.load)
                            .font(.footnote)
                    }
                }
            }
        } else {
            LabeledContent {
                Text("Connected")
                    .foregroundStyle(.green)
            } label: {
                Label(viewModel.aiRegionProfile?.marketingName ?? String(localized: "Current Device"), systemImage: "iphone")
            }
        }
    }

    private var dynamicIslandSection: some View {
        Section("Dynamic Island") {
            tweakRow(.supportsDynamicIsland)
            if viewModel.selectedTweaks.contains(.supportsDynamicIsland) || viewModel.dynamicIslandSubtype != nil {
                Picker("Island Layout", selection: $viewModel.dynamicIslandSubtype) {
                    Text("Keep Current Layout").tag(Int?.none)
                    ForEach(DynamicIslandOption.all) { option in
                        Text(option.title).tag(Int?.some(option.subtype))
                    }
                }
            }
        }
        .onChange(of: viewModel.selectedTweaks.contains(.supportsDynamicIsland)) { _, enabled in
            if !enabled { viewModel.dynamicIslandSubtype = nil }
        }
    }

    @ViewBuilder
    private var modelNameControls: some View {
        Toggle("Change model name in About", isOn: $viewModel.changesModelName)
        if viewModel.changesModelName {
            TextField("Model Name", text: $viewModel.modelName)
                .textInputAutocapitalization(.words)
        }
    }

    private var applyBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "%d pending changes"), viewModel.stagedChangeCount))
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Apply") { viewModel.applySelectedTweaks() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct PlacardPromotionLink: View {
    private let placardURL = URL(string: "https://github.com/frs0n/placard")!

    var body: some View {
        Link(destination: placardURL) {
            HStack(spacing: 12) {
                placardIcon
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Placard")
                        .font(.body.weight(.medium))
                    Text("iPhone 动态壁纸")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(minHeight: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Placard，iPhone 动态壁纸，点击打开 GitHub")
    }

    private var placardIcon: Image {
        guard let url = Bundle.main.url(forResource: "PlacardIcon", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            return Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
        }
        return Image(uiImage: image)
    }
}

private struct DeveloperFooter: View {
    private let douyinURL = URL(string: "https://v.douyin.com/hHHMAlF5bE0/")!
    private let xURL = URL(string: "https://x.com/Frs0n_")!
    private let githubURL = URL(string: "https://github.com/frs0n")!

    var body: some View {
        HStack(spacing: 12) {
            avatarImage
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text("SUSS")
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                socialLink("Douyin", label: "抖音", destination: douyinURL)
                socialLink("X", label: "X", destination: xURL)
                socialLink("GitHub", label: "GitHub", destination: githubURL)
            }
        }
        .frame(minHeight: 44)
    }

    private func socialLink(_ image: String, label: String, destination: URL) -> some View {
        Link(destination: destination) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("SUSS · \(label)")
    }

    private var avatarImage: Image {
        guard let url = Bundle.main.url(forResource: "SUSSAvatar", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else {
            return Image(systemName: "person.crop.circle")
        }
        return Image(uiImage: image)
    }
}

private struct TweakToggle: View {
    let definition: GestaltTweakDefinition
    @Binding var isOn: Bool

    var included = false
    @State private var showsDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(definition.title)
                        if definition.isRisky {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("High Risk")
                        }
                    }
                }
            }
            .disabled(included)
            if definition.isRisky || definition.showsDetails || [.supportsDynamicIsland, .chargeLimit, .alwaysOnDisplayVibrancy].contains(definition.id) {
                Button {
                    showsDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .frame(minWidth: 32, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("About \(definition.title)"))
            }
        }
        .onChange(of: isOn) { _, enabled in
            if enabled && definition.isRisky && !included { showsDetails = true }
        }
        .alert(definition.title, isPresented: $showsDetails) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(definition.detail)
        }
    }
}

private struct BackupLibrary: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsBackupImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        viewModel.runIdentityAudit()
                    } label: {
                        Label("Scan Device Identity", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(viewModel.isBusy)

                    if let report = viewModel.identityAudit {
                        NavigationLink {
                            IdentityReportView(report: report)
                        } label: {
                            if report.isSpoofed {
                                Label {
                                    Text("Device Spoof Detected — \(report.spoofedEntries.count) Errors")
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                            } else if report.hasSiriAIResidue {
                                Label {
                                    Text("Identity OK — Siri AI Keys in Cache")
                                } icon: {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                Label {
                                    Text("Identity Matches This Device")
                                } icon: {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Device Doctor")
                } footer: {
                    Text("Compares the MobileGestalt cache with what the hardware itself reports. Detects leftover device spoofs that break dictation, spoken Siri and Face ID — with or without a backup.")
                }

                Section {
                    Button {
                        viewModel.createBackup()
                    } label: {
                        Label("Back Up Current MobileGestalt", systemImage: "plus.circle.fill")
                    }
                    .disabled(viewModel.plist == nil || viewModel.isBusy)

                    Button {
                        showsBackupImporter = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isBusy)
                }

                if !identityBackups.isEmpty {
                    Section {
                        backupRows(identityBackups)
                    } header: {
                        Text("Siri AI")
                    } footer: {
                        Text("These recovery backups finish Temporary Spoof and AI Expansion: they restore your real identity while every Siri AI key stays. Face ID and dictation work again after restarting, and the apps that appeared during the download stay installed. Only removing the AI keys (Device Doctor → Fix Detected Errors) hides them again.")
                    }
                }

                Section("Local Backups") {
                    if ordinaryBackups.isEmpty {
                        Label("No Backups", systemImage: "archivebox")
                            .foregroundStyle(.secondary)
                    } else {
                        backupRows(ordinaryBackups)
                    }
                }
            }
            .navigationTitle(viewModel.selectedDevice == .appleWatch ? String(localized: "Apple Watch Backups") : String(localized: "Restore"))
            .refreshable { viewModel.refreshBackups() }
            .onAppear { viewModel.refreshBackups() }
            .fileImporter(
                isPresented: $showsBackupImporter,
                allowedContentTypes: [.propertyList],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.importBackup(from: url) }
                case .failure(let error):
                    viewModel.notice = GestaltNotice(kind: .error, message: error.localizedDescription)
                }
            }

        }
    }
    private var identityBackups: [GestaltBackup] {
        viewModel.backups.filter { $0.purpose == .siriAIIdentityRestore }
    }

    private var ordinaryBackups: [GestaltBackup] {
        viewModel.backups.filter { $0.purpose == .standard }
    }

    private func backupRows(_ backups: [GestaltBackup]) -> some View {
        ForEach(backups) { backup in
            BackupRow(backup: backup)
        }
        .onDelete { offsets in
            for index in offsets { viewModel.delete(backups[index]) }
        }
    }

}

// MARK: - Device Doctor report

private struct IdentityReportView: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsFixSheet = false
    @State private var showsFactoryResetConfirmation = false
    let report: DeviceIdentityAudit.Report

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: verdictIcon)
                        .font(.title2)
                        .foregroundStyle(verdictColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdictTitle)
                            .font(.headline)
                        Text("Kernel machine: \(report.machineIdentifier)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Cache vs Hardware") {
                ForEach(report.identityEntries) { entry in
                    entryRow(entry)
                }
            }

            if !report.residueEntries.isEmpty {
                Section {
                    ForEach(report.residueEntries) { entry in
                        entryRow(entry)
                    }
                } header: {
                    Text("Siri AI Keys in Cache")
                } footer: {
                    Text("Activation keys and region values written by Siri AI editors. With a clean identity, leftover activation keys are the leading cause of dictation and spoken Siri staying broken — removing them returns the speech stack to the standard pipeline.")
                }
            }

            if !report.isSpoofed {
                Section {
                    triageRows
                } header: {
                    Text("If Dictation Still Fails")
                } footer: {
                    Text(report.hasSiriAIResidue
                         ? String(localized: "After applying the fix and restarting, also work through this list — especially re-adding the failing dictation languages, whose speech resources were downloaded while the old keys were still active.")
                         : String(localized: "The cache is clean, so any remaining dictation problem is outside MobileGestalt. Work through this list from the top."))
                }
            }

            Section {
                ShareLink(item: report.reportText) {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                }
                if report.isSpoofed || report.hasSiriAIResidue {
                    Button("Fix Detected Errors") { showsFixSheet = true }
                        .disabled(viewModel.isBusy)
                }
            } footer: {
                Text(reportFooter)
            }

            Section("Downloaded Siri AI Models") {
                if viewModel.modelAssetReports.isEmpty {
                    Button("Probe Model Asset Stores") {
                        viewModel.probeModelAssets()
                    }
                } else {
                    ForEach(viewModel.modelAssetReports, id: \.self) { report in
                        Text(report)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Button(role: .destructive) {
                    viewModel.hideDownloadedModelAssets()
                } label: {
                    Label("Hide Downloaded Models (forces redownload)", systemImage: "arrow.down.circle.dashed")
                }
                .disabled(viewModel.isBusy || !viewModel.modelAssetReports.contains { $0.hasPrefix("✓") })
                Button {
                    viewModel.restoreHiddenModelAssets()
                } label: {
                    Label("Restore Hidden Models", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(viewModel.isBusy || viewModel.modelAssetHiddenCount == 0)
                Text("Hides the downloaded Siri AI model bundles so Settings → Apple Intelligence & Siri offers a fresh download — for wedged 'Siri is updating' loops or corrupted bundles. Restart after hiding; re-download needs the eligibility surface (Enable Siri AI in Classic mode) and matching Siri/iPhone language. Restore Hidden Models renames them back, restoring the previous download WITHOUT redownloading. Targets that report ✗ are not reachable with the current exploit class on this build.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear { if !viewModel.modelAssetsProbed { viewModel.probeModelAssets() } }

            Section {
                Button(role: .destructive) {
                    showsFactoryResetConfirmation = true
                } label: {
                    Label("Factory Cache Reset", systemImage: "arrow.counterclockwise.circle.fill")
                }
                .disabled(viewModel.isBusy)
            } footer: {
                Text("Last resort: removes every cached answer so iOS rebuilds a brand-new native cache on restart. All MobileGestalt edits are removed — Siri AI activation, region overrides, cosmetic tweaks. The current file is backed up automatically first.")
            }
        }
        .navigationTitle("Device Doctor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFixSheet) {
            IdentityFixSheet(report: report)
        }
        .confirmationDialog(
            String(localized: "Factory Reset MobileGestalt Cache?"),
            isPresented: $showsFactoryResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear Cache and Restart"), role: .destructive) {
                viewModel.rebuildGestaltCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every MobileGestalt modification is removed and iOS rebuilds a native cache after a full restart. Use this only if the doctor found nothing and dictation is still broken, or as the last resort after failed fixes. A backup is created first.")
        }
    }

    private var verdictTitle: String {
        if report.isSpoofed { return String(localized: "Device Identity Spoofed") }
        if report.hasSiriAIResidue { return String(localized: "Identity Matches — Siri AI Keys Still in Cache") }
        return String(localized: "Identity Matches This Device")
    }

    private var verdictIcon: String {
        report.isSpoofed || report.hasSiriAIResidue
            ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    private var verdictColor: Color {
        report.isSpoofed || report.hasSiriAIResidue ? .orange : .green
    }

    private var reportFooter: String {
        if report.isSpoofed {
            return String(localized: "Every value is shown for confirmation before writing and the current file is backed up automatically. Restart the device after fixing.")
        }
        if report.hasSiriAIResidue {
            return String(localized: "The identity is clean, but leftover Siri AI activation keys can keep the speech stack in a pipeline this device cannot complete. Removing them is reversible — Siri AI can be re-enabled later from the Siri AI tab. Afterwards re-add each failing dictation language so iOS re-downloads its speech resources.")
        }
        return String(localized: "The cache is fully clean, so a leftover spoof or activation key is not the cause of a remaining dictation problem. Work through the checklist, then use Factory Cache Reset only as the last resort.")
    }

    @ViewBuilder private var triageRows: some View {
        Label("Settings → General → Keyboard → Enable Dictation is on", systemImage: "keyboard")
        Label("Settings → General → Keyboard → Dictation Languages includes your language", systemImage: "globe")
        Label("Dictation fails in one language but works in another? Remove that language from Dictation Languages, restart, then re-add it on Wi-Fi — iOS re-downloads fresh speech resources for the repaired identity", systemImage: "arrow.triangle.2.circlepath")
        Label("Settings → Screen Time → Content & Privacy Restrictions → Allowed Apps and Siri & Dictation are not restricted", systemImage: "hand.raised")
        Label("Settings → Siri & Search: Siri is on", systemImage: "waveform")
        Label("Fully restart the iPhone (power off and on) after any cache change — speech daemons keep their state until then", systemImage: "power")
        Label("If nothing helps: Factory Cache Reset below rebuilds a brand-new native cache", systemImage: "arrow.counterclockwise.circle")
    }

    private func entryRow(_ entry: DeviceIdentityAudit.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: iconName(entry.status))
                    .foregroundStyle(iconColor(entry.status))
                Text(entry.title)
            }
            .font(.subheadline)
            if let cached = entry.cachedValue {
                Text("Stored: \(cached)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("Not stored in cache")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let expected = entry.expectedValue, entry.status != .match {
                Text("Expected: \(expected)")
                    .font(.footnote.monospaced())
            }
            if let note = entry.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
    }

    private func iconName(_ status: DeviceIdentityAudit.Entry.Status) -> String {
        switch status {
        case .match: "checkmark.circle.fill"
        case .mismatch: "exclamationmark.triangle.fill"
        case .review: "info.circle"
        case .residue: "sparkles"
        }
    }

    private func iconColor(_ status: DeviceIdentityAudit.Entry.Status) -> Color {
        switch status {
        case .match: .green
        case .mismatch: .orange
        case .review: .secondary
        case .residue: .orange
        }
    }
}

private struct IdentityFixSheet: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @Environment(\.dismiss) private var dismiss
    let report: DeviceIdentityAudit.Report

    @State private var removeSiriOnDevice = false
    @State private var removeSiriAIKeys = false
    @State private var removeRegionOverrides = false
    @State private var didApplyDefaults = false
    @State private var regulatoryModelText = ""
    @State private var showsApplyConfirmation = false

    private var regulatoryModelOverride: String? {
        let trimmed = regulatoryModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var plan: DeviceIdentityAudit.FixPlan? {
        viewModel.identityFixPlan(
            removeSiriOnDevice: removeSiriOnDevice,
            removeSiriAIKeys: removeSiriAIKeys,
            removeRegionOverrides: removeRegionOverrides,
            regulatoryModelOverride: regulatoryModelOverride
        )
    }

    private var needsRegulatoryInput: Bool {
        report.entries.contains {
            $0.id == DeviceIdentityAudit.regulatoryModel && $0.status == .mismatch
        } && !DeviceIdentityAudit.validRegulatory(regulatoryModelOverride)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review each value below. All of them come from this device's hardware report, a verified backup, or the built-in device database.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let plan, plan.hasChanges {
                    Section("Proposed Changes") {
                        ForEach(plan.proposals) { proposal in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposal.title)
                                    .font(.subheadline)
                                if proposal.isRemoval {
                                    Text("Remove stored value \(proposal.currentValue ?? "")")
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(proposal.currentValue ?? "(not stored)")
                                        .font(.footnote.monospaced())
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.down")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(proposal.proposedValue ?? "")
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.green)
                                }
                                Text(proposal.reason)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if needsRegulatoryInput {
                    Section {
                        TextField("A1234", text: $regulatoryModelText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Regulatory Model Number Required")
                    } footer: {
                        Text("The stored value is not a valid A-number. Enter the one from Settings → General → About → Model Number (tap the row to switch to the A-number).")
                    }
                }

                if report.entries.contains(where: { $0.id == DeviceIdentityAudit.siriOnDevice && $0.cachedValue != nil }) {
                    Section {
                        Toggle(isOn: $removeSiriOnDevice) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove On-Device Siri Understanding Flag")
                                Text("Only enable this if your device did not ship with on-device Siri understanding. Removing a flag added by a spoofing editor can restore the on-device speech pipeline.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if report.hasSiriAIResidue {
                    Section {
                        Toggle(isOn: $removeSiriAIKeys) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove Siri AI Activation Keys")
                                Text("Recommended: these keys were written by a Siri AI editor and keep the speech stack in the generative pipeline, which usually keeps dictation broken even when the identity is clean. Removing them is reversible — Siri AI can be re-enabled later from the Siri AI tab.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !report.regionOverrideEntries.isEmpty {
                    Section {
                        Toggle(isOn: $removeRegionOverrides) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove Region Overrides (LL)")
                                Text("Only enable this if this device's real region is not LL/US. iOS recomputes the genuine region after restart.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Apply Fix and Restart") { showsApplyConfirmation = true }
                        .disabled(viewModel.isBusy || !(plan?.hasChanges ?? false) || needsRegulatoryInput)
                } footer: {
                    Text("The current MobileGestalt file is backed up automatically before writing, and the result is verified after writing. Restart the iPhone afterwards so the speech stack and Face ID pick up the repaired identity.")
                }
            }
            .navigationTitle("Fix Detected Errors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !didApplyDefaults {
                    didApplyDefaults = true
                    // Default the AI-key removal on ONLY for keys-only residue
                    // on a clean identity. When the identity is spoofed the
                    // keys are an active stage-1 borrow, and when the CacheData
                    // gate is open with a clean identity the keys are the
                    // finished stage-2 unlock — in both states the doctor's
                    // report says do NOT repair, so pre-enabling the removal
                    // would let one tap cancel the whole unlock.
                    removeSiriAIKeys = report.hasSiriAIResidue
                        && !report.isSpoofed
                        && !report.isStageTwoUnlockActive
                    if let entry = report.entries.first(where: { $0.id == DeviceIdentityAudit.regulatoryModel }),
                       entry.status == .mismatch {
                        regulatoryModelText = entry.cachedValue ?? ""
                    }
                }
            }
            .confirmationDialog(
                String(localized: "Apply Device Doctor Fix?"),
                isPresented: $showsApplyConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Write Repaired Identity"), role: .destructive) {
                    if let plan {
                        viewModel.applyIdentityFix(plan)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the selected activation keys and writes the confirmed identity values to the MobileGestalt cache. The current file is backed up first. Restart the iPhone after this. Afterwards re-add each failing dictation language (remove it, restart, re-add on Wi-Fi) so iOS re-downloads fresh speech resources.")
            }
        }
    }
}

private struct BackupRow: View {
    let backup: GestaltBackup

    var body: some View {
        NavigationLink {
            BackupDetail(backup: backup)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.reason)
                Text(backup.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BackupDetail: View {
    @EnvironmentObject private var viewModel: GestaltViewModel
    @State private var showsRestoreConfirmation = false
    @State private var showsRepairConfirmation = false
    @State private var showsChanges = false
    let backup: GestaltBackup

    var body: some View {
        List {
            Section {
                Text(backup.reason)
                Text(backup.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: backup.byteCount, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            if let record = backup.record,
               record.source == .modification || record.source == .restore || record.source == .identityRecovery {
                Section {
                    DisclosureGroup(isExpanded: $showsChanges) {
                        if record.changes.isEmpty {
                            Text("No Field Changes").foregroundStyle(.secondary)
                        }
                        ForEach(record.changes) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = fieldTitle(for: change) {
                                    Text(title)
                                    Text(change.path.joined(separator: " › "))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(change.path.joined(separator: " › "))
                                        .font(.subheadline.monospaced())
                                }
                                Text(change.before ?? String(localized: "Not Present"))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.down").foregroundStyle(.tertiary)
                                    .accessibilityLabel("Changes to")
                                Text(change.after ?? String(localized: "Not Present"))
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                        }
                    } label: {
                        Text(record.verified ? String(localized: "Changes") : String(localized: "Requested Changes"))
                    }
                }
            }
            Section {
                ShareLink(item: backup.url) { Label("Export Backup", systemImage: "square.and.arrow.up") }
                if backup.purpose == .standard && viewModel.selectedDevice == .iPhone {
                    Button("Repair Dictation & Face ID") { showsRepairConfirmation = true }
                        .disabled(viewModel.isBusy)
                        .confirmationDialog(
                            String(localized: "Repair Dictation and Face ID?"),
                            isPresented: $showsRepairConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(String(localized: "Repair Identity"), role: .destructive) {
                                viewModel.repairDictation(from: backup)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Restores only the original device identity and the on-device Siri capability from this backup. Use this if dictation, spoken Siri or Face ID stopped working after a Siri AI device spoof from any editor. Siri AI, SiriMode and region settings stay enabled. The current file will be backed up before writing.")
                        }
                }
                Button("Restore Backup") { showsRestoreConfirmation = true }
                    .disabled(viewModel.isBusy)
                    .confirmationDialog(
                        backup.purpose == .siriAIIdentityRestore
                            ? String(localized: "Restore Real Identity?")
                            : String(localized: "Restore This MobileGestalt Backup?"),
                        isPresented: $showsRestoreConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(backup.purpose == .siriAIIdentityRestore
                               ? String(localized: "Restore Identity · Keep AI Keys")
                               : String(localized: "Restore and Write"), role: .destructive) {
                            viewModel.restore(backup)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if backup.purpose == .siriAIIdentityRestore {
                            Text("Use this after the Siri AI model download completes. Your original device identity returns and Face ID and dictation work again after restarting. All Siri AI keys — including the iOS 27 expansion flag and the persistence keys — stay, so Image Playground and the dedicated Siri app remain installed. The current file will be backed up before writing.")
                        } else {
                            Text(viewModel.selectedDevice == .appleWatch
                                 ? String(localized: "The current Apple Watch file will be backed up first. The watch interface will restart automatically after restoring.")
                                 : String(localized: "The current file will be backed up first. SpringBoard will refresh automatically after restoring."))
                        }
                    }
            }
        }
        .navigationTitle("Backup Details")
        .navigationBarTitleDisplayMode(.inline)

    }

    private func fieldTitle(for change: GestaltBackupChange) -> String? {
        guard change.path.count == 2, change.path.first == "CacheExtra", let key = change.path.dropFirst().first else {
            return nil
        }
        let matches = GestaltTweakCatalog.definitions.filter { $0.values[key] != nil }
        if matches.count == 1 { return matches[0].title }
        return WatchTweakCatalog.definitions.first { $0.keys.contains(key) }?.title
    }
}

private struct AdvancedGestaltEditor: View {
    @EnvironmentObject private var viewModel: GestaltViewModel

    @State private var searchText = ""
    @State private var activeEditor: FieldEditorRoute?

    private var cacheExtraKeys: [String] {
        filtered(viewModel.plist?.cacheExtraKeys ?? [], section: .cacheExtra)
    }

    private var topLevelKeys: [String] {
        filtered(
            viewModel.plist?.topLevelKeys.filter { $0 != "CacheExtra" } ?? [],
            section: .topLevel
        )
    }

    var body: some View {
        List {
            if viewModel.plist != nil {
                KeySection(
                    title: "CacheExtra",
                    keys: cacheExtraKeys,
                    value: { value(for: PlistKey(section: .cacheExtra, key: $0)) },
                    select: {
                        activeEditor = .edit(
                            PlistKey(section: .cacheExtra, key: $0)
                        )
                    }
                )

                KeySection(
                    title: String(localized: "Top Level"),
                    keys: topLevelKeys,
                    value: { value(for: PlistKey(section: .topLevel, key: $0)) },
                    select: {
                        activeEditor = .edit(
                            PlistKey(section: .topLevel, key: $0)
                        )
                    }
                )
            }
        }
        .navigationTitle("Advanced Field Editor")
        .searchable(text: $searchText, prompt: "Search key or value")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    activeEditor = .addCacheExtra
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add CacheExtra Field")
                .disabled(viewModel.plist == nil || viewModel.isBusy)

                Button("Save", action: viewModel.applyChanges)
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isDirty || viewModel.isBusy)
            }
        }
        .sheet(item: $activeEditor) { editor in
            Group {
                switch editor {
                case .edit(let key):
                    ValueEditor(
                        key: key.key,
                        initialValue: value(for: key),
                        save: { update($0, for: key) },
                        delete: key.section == .cacheExtra
                            ? { deleteCacheExtraField(key.key) }
                            : nil
                    )
                case .addCacheExtra:
                    AddCacheExtraFieldEditor(save: addCacheExtraField)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func filtered(_ keys: [String], section: PlistSection) -> [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return keys }

        return keys.filter { key in
            let reference = PlistKey(section: section, key: key)
            let info = PlistValueInfo.info(for: value(for: reference))
            return key.localizedCaseInsensitiveContains(query)
                || info.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    private func value(for key: PlistKey) -> Any? {
        switch key.section {
        case .cacheExtra:
            viewModel.plist?.cacheExtra[key.key]
        case .topLevel:
            viewModel.plist?.value(forKey: key.key)
        }
    }

    private func update(_ value: Any, for key: PlistKey) {
        guard var plist = viewModel.plist else { return }
        switch key.section {
        case .cacheExtra:
            plist.setCacheExtra(value, forKey: key.key)
        case .topLevel:
            plist.setValue(value, forKey: key.key)
        }
        viewModel.plist = plist
        viewModel.isDirty = true
    }

    private func addCacheExtraField(key: String, value: Any) throws {
        guard var plist = viewModel.plist else { return }
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw AddFieldError.emptyKey
        }
        guard plist.cacheExtra[normalizedKey] == nil else {
            throw AddFieldError.duplicateKey(normalizedKey)
        }

        plist.setCacheExtra(value, forKey: normalizedKey)
        viewModel.plist = plist
        viewModel.isDirty = true
    }

    private func deleteCacheExtraField(_ key: String) {
        guard var plist = viewModel.plist else { return }
        plist.removeCacheExtraValue(forKey: key)
        viewModel.plist = plist
        viewModel.isDirty = true
    }
}

private enum PlistSection: String {
    case cacheExtra
    case topLevel
}

private struct PlistKey: Identifiable {
    let section: PlistSection
    let key: String
    var id: String { "\(section.rawValue)/\(key)" }
}

private enum FieldEditorRoute: Identifiable {
    case edit(PlistKey)
    case addCacheExtra

    var id: String {
        switch self {
        case .edit(let key): "edit/\(key.id)"
        case .addCacheExtra: "add/cacheExtra"
        }
    }
}

private enum AddFieldError: LocalizedError {
    case emptyKey
    case duplicateKey(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            String(localized: "Key cannot be empty.")
        case .duplicateKey(let key):
            String(format: String(localized: "CacheExtra already contains the field: %@"), key)
        }
    }
}

private struct KeySection: View {
    let title: String
    let keys: [String]
    let value: (String) -> Any?
    let select: (String) -> Void

    var body: some View {
        Section(title) {
            if keys.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keys, id: \.self) { key in
                    Button { select(key) } label: {
                        KeyRow(key: key, value: value(key))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct KeyRow: View {
    let key: String
    let value: Any?

    var body: some View {
        let info = PlistValueInfo.info(for: value)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(info.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct ValueEditor: View {
    @Environment(\.dismiss) private var dismiss

    let key: String
    let initialValue: Any?
    let save: (Any) -> Void
    let delete: (() -> Void)?

    @State private var kind: PlistValueKind
    @State private var text: String
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false

    init(
        key: String,
        initialValue: Any?,
        save: @escaping (Any) -> Void,
        delete: (() -> Void)? = nil
    ) {
        self.key = key
        self.initialValue = initialValue
        self.save = save
        self.delete = delete
        let kind = PlistValueKind.kind(of: initialValue)
        _kind = State(initialValue: kind)
        _text = State(initialValue: PlistValueInfo.encode(initialValue, as: kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(PlistValueKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Value") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if delete != nil {
                    Section {
                        Button("Delete Field", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(key)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: commit)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete CacheExtra Field?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    delete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The field will be removed from the file after you return to the editor and tap Save.")
            }
        }
    }

    private func commit() {
        do {
            save(try PlistValueInfo.parse(text, as: kind))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddCacheExtraFieldEditor: View {
    @Environment(\.dismiss) private var dismiss

    let save: (String, Any) throws -> Void

    @State private var key = ""
    @State private var kind: PlistValueKind = .string
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    LabeledContent("Location", value: "CacheExtra")
                    TextField("Key", text: $key)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(PlistValueKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Value") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add", action: commit)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func commit() {
        do {
            let value = try PlistValueInfo.parse(text, as: kind)
            try save(key, value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GestaltViewModel())
}
