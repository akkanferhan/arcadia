import Foundation
import Testing
@testable import Arcadia

@Suite struct RetroAchievementsAPITests {
    @Test func loginRequestMatchesRcheevos() throws {
        let request = RetroAchievementsAPI.loginRequest(username: "Player One", password: "p&ss=w+rd/ü")
        #expect(request.url?.absoluteString == "https://retroachievements.org/dorequest.php")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Arcadia/") == true)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body == "r=login2&u=Player%20One&p=p%26ss%3Dw%2Brd%2F%C3%BC")
    }

    @Test func readsTheTokenFromASuccessfulLogin() throws {
        let json = #"{"Success":true,"User":"PlayerOne","AvatarUrl":"https://media.retroachievements.org/UserPic/PlayerOne.png","Token":"AbCdEfGhIjKlMnOp","Score":120,"SoftcoreScore":4,"Messages":0,"Permissions":1,"AccountType":"Registered"}"#
        let login = try RetroAchievementsAPI.parseLogin(Data(json.utf8))
        #expect(login == .init(username: "PlayerOne", token: "AbCdEfGhIjKlMnOp"))
    }

    @Test func reportsWrongPasswords() {
        let json = #"{"Success":false,"Status":401,"Code":"invalid_credentials","Error":"Invalid User/Password combination. Please try again."}"#
        #expect(throws: RetroAchievementsAPI.Failure.invalidCredentials) {
            try RetroAchievementsAPI.parseLogin(Data(json.utf8))
        }
    }

    @Test func passesOtherServerErrorsOn() {
        let json = #"{"Success":false,"Status":403,"Code":"access_denied","Error":"Access denied. Please verify your email address."}"#
        #expect(throws: RetroAchievementsAPI.Failure.server("Access denied. Please verify your email address.")) {
            try RetroAchievementsAPI.parseLogin(Data(json.utf8))
        }
    }

    @Test func rejectsUnreadableAnswers() {
        #expect(throws: RetroAchievementsAPI.Failure.unreadable) { try RetroAchievementsAPI.parseLogin(Data("<html>".utf8)) }
        #expect(throws: RetroAchievementsAPI.Failure.unreadable) {
            try RetroAchievementsAPI.parseLogin(Data(#"{"Success":true,"User":"PlayerOne"}"#.utf8))
        }
    }
}

private final class MemoryStore: AchievementsCredentialStore, @unchecked Sendable {
    var login: RetroAchievementsAPI.Login?
    func load() -> RetroAchievementsAPI.Login? { login }
    func save(_ login: RetroAchievementsAPI.Login) throws { self.login = login }
    func delete() throws { login = nil }
}

@MainActor
@Suite struct RetroAchievementsAccountTests {
    @Test func signingInKeepsOnlyNameAndToken() async {
        let store = MemoryStore()
        let defaults = MemoryDefaults()
        let account = RetroAchievements(store: store, defaults: defaults) { user, password in
            #expect(user == "playerone")
            #expect(password == "secret")
            return .init(username: "PlayerOne", token: "token123")
        }
        #expect(account.settings == AchievementsSettings(username: nil, token: nil, enabled: true, hardcore: false))
        await account.signIn(username: " playerone ", password: "secret")
        #expect(store.login == .init(username: "PlayerOne", token: "token123"))
        #expect(account.settings.isActive)
        #expect(account.lastError == nil)

        account.hardcore = true
        #expect(account.settings.isHardcore)
        #expect(defaults.bool(forKey: "achievementsHardcore"))
        account.enabled = false
        #expect(!account.settings.isActive && !account.settings.isHardcore)

        account.signOut()
        #expect(store.login == nil)
        #expect(!account.settings.isSignedIn)
    }

    @Test func failedSignInShowsTheReason() async {
        let store = MemoryStore()
        let defaults = MemoryDefaults()
        let account = RetroAchievements(store: store, defaults: defaults) { _, _ in
            throw RetroAchievementsAPI.Failure.invalidCredentials
        }
        await account.signIn(username: "playerone", password: "wrong")
        #expect(account.login == nil)
        #expect(store.login == nil)
        #expect(account.lastError == RetroAchievementsAPI.Failure.invalidCredentials.localizedDescription)
    }

    @Test func remembersAnEarlierSignIn() {
        let store = MemoryStore()
        store.login = .init(username: "PlayerOne", token: "token123")
        let defaults = MemoryDefaults()
        let account = RetroAchievements(store: store, defaults: defaults) { _, _ in fatalError("no network in tests") }
        #expect(account.settings.username == "PlayerOne")
        #expect(account.settings.token == "token123")
    }
}

@Suite struct AchievementsPresetTests {
    private let on = AchievementsSettings(username: "PlayerOne", token: "token123", enabled: true, hardcore: true)
    private let disabled = AchievementsSettings(username: "PlayerOne", token: "token123", enabled: false, hardcore: true)

    @Test func retroArchGetsTheTokenAndNeverAPassword() throws {
        let folder = TemporaryFolder()
        let file = folder.write("retroarch.cfg", text: "cheevos_password = \"old\"\nvideo_driver = \"vulkan\"\n")
        try INIFile.update(file) { $0.set(Presets.retroArchAchievements(on)) }
        let text = folder.read("retroarch.cfg")
        #expect(text.contains("cheevos_enable = \"true\""))
        #expect(text.contains("cheevos_hardcore_mode_enable = \"true\""))
        #expect(text.contains("cheevos_username = \"PlayerOne\""))
        #expect(text.contains("cheevos_token = \"token123\""))
        #expect(text.contains("cheevos_password = \"\""))
        #expect(text.contains("video_driver = \"vulkan\""))

        // Signing out clears the account and turns achievements (and RetroArch's default hardcore) off.
        try INIFile.update(file) { $0.set(Presets.retroArchAchievements(.off)) }
        let cleared = folder.read("retroarch.cfg")
        #expect(cleared.contains("cheevos_enable = \"false\""))
        #expect(cleared.contains("cheevos_hardcore_mode_enable = \"false\""))
        #expect(cleared.contains("cheevos_username = \"\""))
        #expect(cleared.contains("cheevos_token = \"\""))
    }

    @Test func disabledAchievementsAreTurnedOffEverywhere() {
        #expect(Presets.retroArchAchievements(disabled)["cheevos_enable"] == "\"false\"")
        #expect(Presets.retroArchAchievements(disabled)["cheevos_hardcore_mode_enable"] == "\"false\"")
        #expect(Presets.duckStationAchievements(disabled, machineKey: "k")["Enabled"] == "false")
        #expect(Presets.duckStationAchievements(disabled, machineKey: "k")["ChallengeMode"] == "false")
        #expect(Presets.ppssppAchievements(disabled)["AchievementsEnable"] == "False")
        #expect(Presets.ppssppAchievements(disabled)["AchievementsChallengeMode"] == "False")
        #expect(Presets.dolphinAchievements(disabled)["Enabled"] == "False")
        #expect(Presets.dolphinAchievements(disabled)["HardcoreEnabled"] == "False")
        #expect(Presets.flycastAchievements(disabled)["Enabled"] == "no")
        #expect(Presets.flycastAchievements(disabled)["HardcoreMode"] == "no")
        // Still signed in, so the account stays for when achievements are turned back on.
        #expect(Presets.dolphinAchievements(disabled)["ApiToken"] == "token123")
    }

    @Test func everyEmulatorGetsItsOwnKeys() {
        #expect(Presets.dolphinAchievements(on) == ["Enabled": "True", "HardcoreEnabled": "True",
                                                     "Username": "PlayerOne", "ApiToken": "token123"])
        #expect(Presets.flycastAchievements(on) == ["Enabled": "yes", "HardcoreMode": "yes",
                                                     "UserName": "PlayerOne", "Token": "token123"])
        #expect(Presets.ppssppAchievements(on) == ["AchievementsEnable": "True", "AchievementsChallengeMode": "True",
                                                    "AchievementsUserName": "PlayerOne"])
        let duck = Presets.duckStationAchievements(on, machineKey: "00112233445566778899aabbccddeeff")
        #expect(duck["Enabled"] == "true")
        #expect(duck["ChallengeMode"] == "true")
        #expect(duck["Username"] == "PlayerOne")
        #expect(DuckStationToken.decrypt(duck["Token"] ?? "", username: "PlayerOne",
                                         machineKey: "00112233445566778899aabbccddeeff") == "token123")
        let signedOut = Presets.duckStationAchievements(.off, machineKey: "k")
        #expect(signedOut["Username"] == "" && signedOut["Token"] == "" && signedOut["LoginTimestamp"] == "")
    }

    @Test func duckStationTokenMatchesDuckStationsEncryption() {
        // Reference made with Python's hashlib and `openssl enc -aes-128-cbc -nopad` following
        // DuckStation's EncryptLoginToken.
        let machine = "00112233445566778899aabbccddeeff"
        let encrypted = DuckStationToken.encrypt("AbCdEfGhIjKlMnOpQrSt", username: "Player1", machineKey: machine)
        #expect(encrypted == "W2LAjTsqUL4pPPpgsI1Xaf8o6Zt7PG6kbm0ESD3+PrA=")
        #expect(DuckStationToken.decrypt(encrypted, username: "Player1", machineKey: machine) == "AbCdEfGhIjKlMnOpQrSt")
        #expect(DuckStationToken.decrypt(encrypted, username: "Player2", machineKey: machine) != "AbCdEfGhIjKlMnOpQrSt")
        #expect(DuckStationToken.machineKey().count == 32)
    }

    @Test func ppssppKeepsItsTokenInASecretFile() throws {
        let folder = TemporaryFolder()
        let system = folder.url.appendingPathComponent("PSP/SYSTEM")
        try Presets.writePPSSPPToken(on, system: system)
        #expect(folder.read("PSP/SYSTEM/ppsspp_retroachievements.dat") == "token123")
        try Presets.writePPSSPPToken(.off, system: system)
        #expect(!FileManager.default.fileExists(atPath: system.appendingPathComponent("ppsspp_retroachievements.dat").path))
    }
}
