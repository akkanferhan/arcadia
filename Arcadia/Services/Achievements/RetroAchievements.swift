import Foundation
import Observation

/// What presets write into each emulator for RetroAchievements.
struct AchievementsSettings: Equatable, Sendable {
    var username: String?
    var token: String?
    var enabled = false
    var hardcore = false

    static let off = AchievementsSettings()

    var isSignedIn: Bool { !(username ?? "").isEmpty && !(token ?? "").isEmpty }
    /// Achievements are on only with an account; otherwise every emulator gets them turned off.
    var isActive: Bool { enabled && isSignedIn }
    var isHardcore: Bool { isActive && hardcore }
}

/// The sign-in request RetroArch, DuckStation, PPSSPP and Dolphin make through rcheevos:
/// `POST https://retroachievements.org/dorequest.php` with `r=login2&u=<user>&p=<password>`.
enum RetroAchievementsAPI {
    static let endpoint = URL(string: "https://retroachievements.org/dorequest.php")!

    struct Login: Equatable, Sendable {
        /// The account name as the server spells it.
        let username: String
        let token: String
    }

    enum Failure: LocalizedError, Equatable {
        case invalidCredentials
        case server(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: String(localized: "The username or password is incorrect.")
            case .server(let message): message
            case .unreadable: String(localized: "RetroAchievements sent an answer Arcadia couldn't read. Try again later.")
            }
        }
    }

    static func loginRequest(username: String, password: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.setValue("Arcadia/\(version) (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(formEncoded([("r", "login2"), ("u", username), ("p", password)]).utf8)
        request.timeoutInterval = 30
        return request
    }

    /// `application/x-www-form-urlencoded`, escaping everything but unreserved characters.
    static func formEncoded(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }

    /// Reads the server's JSON: `{"Success":true,"User":"…","Token":"…"}` or
    /// `{"Success":false,"Error":"…","Code":"invalid_credentials"}` (also sent with HTTP 401).
    static func parseLogin(_ data: Data) throws -> Login {
        struct Response: Decodable {
            let Success: Bool?
            let User: String?
            let Token: String?
            let Error: String?
            let Code: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.unreadable }
        if response.Success == true, let user = response.User, !user.isEmpty, let token = response.Token, !token.isEmpty {
            return Login(username: user, token: token)
        }
        if response.Code == "invalid_credentials" { throw Failure.invalidCredentials }
        if let message = response.Error, !message.isEmpty { throw Failure.server(message) }
        throw Failure.unreadable
    }

    static func login(username: String, password: String, session: URLSession = .shared) async throws -> Login {
        let (data, _) = try await session.data(for: loginRequest(username: username, password: password))
        return try parseLogin(data)
    }
}

/// Where the RetroAchievements username and token live. Never the password.
protocol AchievementsCredentialStore: Sendable {
    func load() -> RetroAchievementsAPI.Login?
    func save(_ login: RetroAchievementsAPI.Login) throws
    func delete() throws
}

/// The player's RetroAchievements account and switches, used by every preset.
@MainActor
@Observable
final class RetroAchievements {
    static let shared = RetroAchievements()

    private let store: any AchievementsCredentialStore
    private let defaults: UserDefaults
    private let signIn: @Sendable (String, String) async throws -> RetroAchievementsAPI.Login

    private(set) var login: RetroAchievementsAPI.Login?
    private(set) var isSigningIn = false
    private(set) var lastError: String?

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "achievementsEnabled") }
    }
    var hardcore: Bool {
        didSet { defaults.set(hardcore, forKey: "achievementsHardcore") }
    }

    init(store: any AchievementsCredentialStore = KeychainCredentialStore(),
         defaults: UserDefaults = .standard,
         signIn: @escaping @Sendable (String, String) async throws -> RetroAchievementsAPI.Login = {
             try await RetroAchievementsAPI.login(username: $0, password: $1)
         }) {
        self.store = store
        self.defaults = defaults
        self.signIn = signIn
        login = store.load()
        enabled = defaults.object(forKey: "achievementsEnabled") as? Bool ?? true
        hardcore = defaults.bool(forKey: "achievementsHardcore")
    }

    var settings: AchievementsSettings {
        AchievementsSettings(username: login?.username, token: login?.token, enabled: enabled, hardcore: hardcore)
    }

    /// Exchanges the password for a token once; only the token is kept.
    func signIn(username: String, password: String) async {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty, !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let login = try await signIn(username, password)
            try store.save(login)
            self.login = login
        } catch let failure as RetroAchievementsAPI.Failure {
            lastError = failure.localizedDescription
        } catch let error as URLError {
            lastError = error.code == .notConnectedToInternet || error.code == .timedOut || error.code == .cannotFindHost
                ? String(localized: "Couldn't reach RetroAchievements. Check your internet connection.")
                : error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Forgets the account; the next launch removes it from every emulator.
    func signOut() {
        try? store.delete()
        login = nil
        lastError = nil
    }
}
