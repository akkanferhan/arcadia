import CommonCrypto
import CryptoKit
import Foundation

/// RetroAchievements keys for every emulator that supports it, taken from each emulator's source.
/// Achievements are always written explicitly: on with an account, off otherwise, and a signed-out
/// player's name and token are cleared everywhere.
extension Presets {
    /// RetroArch `retroarch.cfg` (configuration.c, settings_def_cheevos_account.h).
    static func retroArchAchievements(_ a: AchievementsSettings) -> [String: String] {
        func quoted(_ value: String) -> String { "\"\(value)\"" }
        return [
            "cheevos_enable": quoted(a.isActive ? "true" : "false"),
            // RetroArch defaults to hardcore, so it is always written.
            "cheevos_hardcore_mode_enable": quoted(a.isHardcore ? "true" : "false"),
            "cheevos_username": quoted(a.isSignedIn ? a.username ?? "" : ""),
            "cheevos_token": quoted(a.isSignedIn ? a.token ?? "" : ""),
            // RetroArch logs in with the token; a stored password is never needed.
            "cheevos_password": quoted(""),
        ]
    }

    /// DuckStation `settings.ini` `[Cheevos]` (settings.cpp, achievements.cpp). DuckStation only
    /// accepts a token encrypted for this Mac.
    static func duckStationAchievements(_ a: AchievementsSettings,
                                        machineKey: String = DuckStationToken.machineKey()) -> [String: String] {
        var values = [
            "Enabled": a.isActive ? "true" : "false",
            "ChallengeMode": a.isHardcore ? "true" : "false",
        ]
        if a.isSignedIn, let username = a.username, let token = a.token {
            values["Username"] = username
            values["Token"] = DuckStationToken.encrypt(token, username: username, machineKey: machineKey)
        } else {
            values.merge(["Username": "", "Token": "", "LoginTimestamp": ""]) { $1 }
        }
        return values
    }

    /// PPSSPP `ppsspp.ini` `[Achievements]` (Core/Config.cpp). The token lives in
    /// `PSP/SYSTEM/ppsspp_retroachievements.dat` (NativeSaveSecret in UI/NativeApp.cpp).
    static func ppssppAchievements(_ a: AchievementsSettings) -> [String: String] {
        [
            "AchievementsEnable": a.isActive ? "True" : "False",
            // PPSSPP defaults to hardcore too.
            "AchievementsChallengeMode": a.isHardcore ? "True" : "False",
            "AchievementsUserName": a.isSignedIn ? a.username ?? "" : "",
        ]
    }

    static func writePPSSPPToken(_ a: AchievementsSettings, system: URL) throws {
        let file = system.appendingPathComponent("ppsspp_retroachievements.dat")
        if a.isSignedIn, let token = a.token {
            try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
            try Data(token.utf8).write(to: file, options: .atomic)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Dolphin `Config/RetroAchievements.ini` `[Achievements]` (Core/Config/AchievementSettings.cpp).
    static func dolphinAchievements(_ a: AchievementsSettings) -> [String: String] {
        [
            "Enabled": a.isActive ? "True" : "False",
            "HardcoreEnabled": a.isHardcore ? "True" : "False",
            "Username": a.isSignedIn ? a.username ?? "" : "",
            "ApiToken": a.isSignedIn ? a.token ?? "" : "",
        ]
    }

    /// Flycast `emu.cfg` `[achievements]` (core/cfg/option.cpp).
    static func flycastAchievements(_ a: AchievementsSettings) -> [String: String] {
        [
            "Enabled": a.isActive ? "yes" : "no",
            "HardcoreMode": a.isHardcore ? "yes" : "no",
            "UserName": a.isSignedIn ? a.username ?? "" : "",
            "Token": a.isSignedIn ? a.token ?? "" : "",
        ]
    }
}

/// DuckStation's token encryption (achievements.cpp, EncryptLoginToken): the key is
/// SHA-256(machine key + username) hashed 100 more times; AES-128-CBC with the first half as key
/// and the second half as IV, zero padding, then Base64. The machine key is the hex host UUID.
enum DuckStationToken {
    static func machineKey() -> String {
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var wait = timespec()
        guard gethostuuid(&uuid, &wait) == 0 else { return String(format: "%08X", gethostid()) }
        return withUnsafeBytes(of: uuid) { $0.map { String(format: "%02x", $0) }.joined() }
    }

    static func key(username: String, machineKey: String) -> [UInt8] {
        var key = Array(SHA256.hash(data: Data((machineKey + username).utf8)))
        for _ in 0..<100 { key = Array(SHA256.hash(data: key)) }
        return key
    }

    static func encrypt(_ token: String, username: String, machineKey: String) -> String {
        crypt(CCOperation(kCCEncrypt), Array(token.utf8).padded(), username: username, machineKey: machineKey)
            .map { Data($0).base64EncodedString() } ?? ""
    }

    static func decrypt(_ encrypted: String, username: String, machineKey: String) -> String? {
        guard let data = Data(base64Encoded: encrypted), data.count % kCCBlockSizeAES128 == 0,
              let plain = crypt(CCOperation(kCCDecrypt), Array(data), username: username, machineKey: machineKey) else { return nil }
        return String(decoding: plain.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func crypt(_ operation: CCOperation, _ input: [UInt8], username: String, machineKey: String) -> [UInt8]? {
        let key = key(username: username, machineKey: machineKey)
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), 0, Array(key[0..<16]), kCCKeySizeAES128,
                             Array(key[16..<32]), input, input.count, &output, output.count, &moved)
        return status == kCCSuccess ? Array(output.prefix(moved)) : nil
    }
}

private extension Array where Element == UInt8 {
    /// Zero bytes up to the next AES block, as DuckStation pads.
    func padded() -> [UInt8] {
        let block = kCCBlockSizeAES128
        return self + [UInt8](repeating: 0, count: (block - count % block) % block)
    }
}
