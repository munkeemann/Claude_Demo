import InventoryCore
import SwiftUI

/// API key (Keychain), model choice, and a connection test.
struct ClaudeSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(ModelPreference.key) private var modelRaw = ClaudeModel.default.rawValue

    @State private var keyDraft = ""
    @State private var testState: TestState = .idle
    @State private var errorMessage: String?

    enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        Section {
            if environment.hasAPIKey {
                LabeledContent("API key") {
                    Label("Saved in Keychain", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                Button("Remove API Key", role: .destructive) {
                    do {
                        try environment.removeAPIKey()
                        testState = .idle
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } else {
                SecureField("sk-ant-…", text: $keyDraft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save API Key") {
                    do {
                        try environment.saveAPIKey(keyDraft)
                        keyDraft = ""
                        testConnection()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Picker("Model", selection: $modelRaw) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
            .onChange(of: modelRaw) { _, _ in testState = .idle }

            if environment.hasAPIKey {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        testStatusView
                    }
                }
                .disabled(testState == .testing)
            }
        } header: {
            Text("Claude")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedModel.summary)
                Text("Your key is stored in the iOS Keychain on this device only. Receipt text and your ingredient list are sent to Anthropic when you use those features. Get a key at console.anthropic.com.")
            }
        }
        .errorAlert($errorMessage)
    }

    private var selectedModel: ClaudeModel {
        ClaudeModel(rawValue: modelRaw) ?? .default
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.iconOnly)
        case .failure(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.trailing)
        }
    }

    private func testConnection() {
        testState = .testing
        let llm = environment.llm
        Task {
            do {
                try await llm.verify()
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
