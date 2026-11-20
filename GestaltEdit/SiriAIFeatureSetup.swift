import SwiftUI

// Post-activation walkthrough for everything the Siri AI capability flags can
// unlock, in dependency order, plus an honest list of what no device-side
// edit can force (server-side eligibility, region provider catalogs and
// hardware-gated features). Guides only — no MobileGestalt writes here.
struct SiriAIFeatureSetupView: View {
    var body: some View {
        List {
            Section {
                Text("Each step below needs the previous one. Work top to bottom after enabling Siri AI, and restart the iPhone after every cache change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Setup") {
                featureRow(1, "Activate Siri AI",
                           "Tools → Region → Enable Siri AI → Apply, then restart. Start in Dictation Safe; only switch to Temporary Spoof if Settings refuses the model download, and use “Remove Device Spoof” once the download finishes.")
                featureRow(2, "Set Siri language",
                           "Settings → Apple Intelligence & Siri → Language → English (New Zealand). It is an Apple Intelligence language and matches the dictation language that works on this device, so features and dictation stay consistent.")
                featureRow(3, "Download the models",
                           "Settings → Apple Intelligence & Siri → turn on Apple Intelligence and let the Siri and image models download over Wi-Fi. On unsupported devices this step may only pass while the temporary spoof is active.")
            }

            Section("Features that appear") {
                featureRow(4, "Image tools",
                           "Image Playground appears as its own app and inside Messages; Genmoji is created in the emoji search field; Image Wand lives in the Notes drawing palette; Clean Up in Photos erases objects from pictures; Writing Tools work in most text fields once the image models are present.")
                featureRow(5, "The new Siri app",
                           "After the model download Siri becomes the full-screen experience with follow-up requests and type-to-Siri. If the old Siri interface remains, recheck the Siri language from step 2 — the new design is language-gated.")
                featureRow(6, "Siri app actions",
                           "This is Siri's expanded control over the phone: sending messages, editing notes, moving files and running in-app commands. Apps expose these actions as their developers adopt App Intents — there is no device-side switch for apps that lack the integration.")
                featureRow(7, "On-screen awareness",
                           "With the models downloaded, the new Siri reads the current screen and acts on it. If actions stay unavailable, recheck the Siri language from step 2 — awareness tracks the Siri language, not the keyboard language.")
                featureRow(8, "Personal context",
                           "Settings → Apple Intelligence & Siri → enable the data Siri may use (Messages, Mail, Photos and more). Personal context is built on the on-device semantic index created after the model download; new data is indexed in the background.")
                featureRow(9, "ChatGPT extension",
                           "Settings → Apple Intelligence & Siri → ChatGPT → Set Up. Basic requests work without an account; signing in unlocks account features. Extra providers beyond what Apple serves to your region cannot be added from the device.")
                featureRow(10, "Camera intelligence",
                           "Visual Intelligence needs its own model download plus a launch path your hardware supports (Camera Control, Action Button, Control Center or the Camera app, depending on the iOS version). Devices without the required hardware may never see it — no Gestalt edit can force it.")
            }

            Section {
                Text("No device-side edit can force server-gated features: availability still depends on Apple's servers, your Apple ID region, and hardware-gated features such as Visual Intelligence. Dictation-safe mode never modifies device identity — if dictation wedges again, Device Doctor → Fix Detected Errors removes the extra flags.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What cannot be forced")
            }
        }
        .navigationTitle("Siri AI Feature Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featureRow(_ index: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
