import SwiftUI

/// Settings section for signing in to RetroAchievements once for every emulator.
struct AchievementsSettingsSection: View {
    @Bindable private var achievements = RetroAchievements.shared
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Section {
            if let login = achievements.login {
                LabeledContent("Signed in as") {
                    HStack {
                        Text(login.username).foregroundStyle(.secondary)
                        Button("Sign Out") { achievements.signOut() }
                    }
                }
                Toggle("Enable achievements", isOn: $achievements.enabled)
                Toggle("Hardcore mode", isOn: $achievements.hardcore)
                    .disabled(!achievements.enabled)
            } else {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                HStack {
                    if achievements.isSigningIn { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Create Account…") {
                        NSWorkspace.shared.open(URL(string: "https://retroachievements.org/createaccount.php")!)
                    }
                    Button("Sign In", action: signIn)
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty
                                  || achievements.isSigningIn)
                }
            }
            if let error = achievements.lastError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("RetroAchievements")
        } footer: {
            Group {
                if achievements.login == nil {
                    Text("Sign in once with your RetroAchievements account to earn achievements in RetroArch, DuckStation, PPSSPP, Dolphin and Flycast. Arcadia keeps only a sign-in token in your Keychain, never your password.")
                } else {
                    Text("Hardcore mode turns off save states, rewind and cheats, so games always start from the beginning. Changes apply the next time you start a game.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func signIn() {
        let password = password
        Task {
            await achievements.signIn(username: username, password: password)
            if achievements.login != nil { self.password = "" }
        }
    }
}
