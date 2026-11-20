import SwiftUI

// Post-activation walkthrough for everything the Siri AI capability flags can
// unlock, in dependency order, plus an honest list of what no device-side
// edit can force (server-side eligibility, region availability and
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
                           "Tools → Region → Enable Siri AI → Apply, then restart. Dictation Safe only lights up the new Siri interface — it never downloads the models, because eligibility checks require an eligible device identity. For the apps pick Temporary Spoof or AI Expansion: the borrowed identity lets the model download start.")
                featureRow(2, "Set Siri language",
                           "Settings → Apple Intelligence & Siri → Language → English (New Zealand). It is an Apple Intelligence language and matches the dictation language that works on this device, so features and dictation stay consistent.")
                featureRow(3, "Download the models",
                           "Settings → Apple Intelligence & Siri → turn on Apple Intelligence and let the Siri and image models download over Wi-Fi (about 3 GB — keep it uninterrupted). Temporarily turn off Find My iPhone and Stolen Device Protection for the setup window, and make sure you are signed into your Apple Account. The download only passes while the eligible identity from step 1 is active — dictation-safe flags alone are never enough.")
                featureRow(4, "Finish the unlock: restore identity, keep AI keys",
                           "Restore tab → the recovery backup → “Restore Identity · Keep AI Keys”, then restart. The real identity returns while every AI key stays — that combination is what makes Image Playground and the dedicated Siri app appear. They appear AFTER this step, not while the borrow is active: keeping the borrowed identity past the download causes a model signature mismatch and the apps never show up. Then toggle Apple Intelligence off and back on once.")
            }

            Section("Features that appear") {
                featureRow(5, "Image tools",
                           "Image Playground appears as its own app and inside Messages; Genmoji is created in the emoji search field; Image Wand lives in the Notes drawing palette; Clean Up in Photos erases objects from pictures; Writing Tools work in most text fields once the image models are present. These survive the identity revert while the AI keys stay — only removing the keys (Device Doctor) hides them again.")
                featureRow(6, "The new Siri app",
                           "After the download AND the identity revert (step 4) the dedicated Siri app appears on the Home Screen and Siri becomes the full-screen experience with follow-up requests and type-to-Siri, with the conversation history synced across your devices via iCloud. If it is missing: the revert never happened, the models are still downloading, or the Siri language from step 2 was never applied — the new design is language-gated. Toggle Apple Intelligence off/on once and restart.")
                featureRow(7, "Siri app actions",
                           "This is Siri's expanded control over the phone: sending messages, editing notes, moving files and running in-app commands. Apps expose these actions as their developers adopt App Intents — there is no device-side switch for apps that lack the integration.")
                featureRow(8, "On-screen awareness",
                           "With the models downloaded, the new Siri reads the current screen and acts on it. If actions stay unavailable, recheck the Siri language from step 2 — awareness tracks the Siri language, not the keyboard language.")
                featureRow(9, "Personal context",
                           "Settings → Apple Intelligence & Siri → enable the data Siri may use (Messages, Mail, Photos and more). Personal context is built on the on-device semantic index created after the model download; new data is indexed in the background.")
                featureRow(10, "ChatGPT extension",
                           "Settings → Apple Intelligence & Siri → ChatGPT → Set Up. Basic requests work without an account; signing in unlocks account features. Extra providers beyond what Apple serves to your region cannot be added from the device.")
                featureRow(11, "Camera intelligence",
                           "Visual Intelligence needs its own model download plus a launch path your hardware supports (Camera Control, Action Button, Control Center or the Camera app, depending on the iOS version). Devices without the required hardware may never see it — no Gestalt edit can force it.")
            }

            Section {
                Text("No device-side edit can force server-gated features: availability still depends on Apple's servers and your Apple Account region. Siri AI is not available in China mainland and is not initially available in the EU for iPhone and iPad — no Gestalt edit changes that, and a China-mainland or EU Apple Account can keep the apps away even with every key set. Hardware-gated features such as Visual Intelligence may also never appear. Only removing the AI keys (Device Doctor → Fix Detected Errors) hides the apps again; the identity revert keeps them.")
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
