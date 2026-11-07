import SwiftUI

struct SignInView: View {
    @ObservedObject var cloud: CloudSyncStore
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 100, height: 100)
                .background(Color.mint, in: RoundedRectangle(cornerRadius: 30))
            VStack(spacing: 8) {
                Text("WALKON").font(.system(size: 25, weight: .black, design: .rounded)).tracking(4)
                Text("Your walks. Your progress. Securely backed up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                if codeSent {
                    Text("Enter your six-digit email code").font(.headline)
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.monospacedDigit())
                    Button(action: verifyCode) {
                        actionLabel("Verify and continue")
                    }
                    .disabled(isWorking || code.count != 6)
                    Button("Use a different email") {
                        code = ""
                        codeSent = false
                        message = nil
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Sign in to sync your data").font(.headline)
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button(action: sendCode) {
                        actionLabel("Send sign-in code")
                    }
                    .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if isWorking { ProgressView().frame(maxWidth: .infinity) }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Use the email address already registered to your account. WALKON will not create a new account.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
            Spacer()
            Text("Your activity stays on this iPhone and syncs to your private account after sign-in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.055, blue: 0.07))
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Spacer()
            Text(title).font(.headline)
            Spacer()
        }
        .padding(14)
        .foregroundStyle(.black)
        .background(Color.mint, in: Capsule())
    }

    private func sendCode() {
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.sendSignInCode(to: email)
                codeSent = true
                message = "Check your inbox for the code."
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func verifyCode() {
        isWorking = true
        message = nil
        Task {
            do {
                try await cloud.verifySignInCode(email: email, code: code)
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
