// GoogleDriveBackup.swift
// Optional backup of personal data to the user's Google Drive.
//
// Design notes:
// - No third-party SDK. OAuth 2.0 with PKCE runs through
//   ASWebAuthenticationSession; Drive calls go over URLSession.
// - Only the Drive "appDataFolder" scope is requested: the app sees nothing
//   in the user's Drive except its own private app folder.
// - The refresh token is kept in the iOS Keychain, never in UserDefaults.
// - Requires a GoogleOAuth.plist with a ClientID (see GoogleOAuth.plist.template).
//   Without it the Backup section of Settings explains the one-time setup.
//
// All network use happens only after the user explicitly signs in (consent).

import AuthenticationServices
import CryptoKit
import Foundation

public enum DriveBackupError: Error, LocalizedError {
    case notConfigured
    case notSignedIn
    case authCancelled
    case authFailed(String)
    case networkFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google sign-in is not configured yet. See Settings for setup steps."
        case .notSignedIn: return "Please sign in with Google first."
        case .authCancelled: return "Sign-in was cancelled."
        case .authFailed(let m): return "Sign-in failed: \(m)"
        case .networkFailed(let m): return "Network error: \(m)"
        }
    }
}

private enum Keychain {
    static let service = "gw.google.drive"

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
public final class GoogleDriveBackup: NSObject, ObservableObject {
    public static let backupFileName = "godsword-backup.json"
    private static let refreshAccount = "refreshToken"
    private static let emailAccount = "accountEmail"
    private static let scope = "https://www.googleapis.com/auth/drive.appdata"

    @Published public private(set) var isSignedIn = false
    @Published public private(set) var accountEmail: String?
    private var authSession: ASWebAuthenticationSession?

    public override init() {
        super.init()
        isSignedIn = Self.storedRefreshToken != nil
        accountEmail = Keychain.load(account: Self.emailAccount)
    }

    // MARK: - Configuration

    /// The OAuth client ID from GoogleOAuth.plist, nil when not configured.
    public static var clientID: String? {
        guard let url = Bundle.main.url(forResource: "GoogleOAuth", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["ClientID"] as? String, !id.isEmpty, !id.hasPrefix("YOUR_")
        else { return nil }
        return id
    }

    public static var isConfigured: Bool { clientID != nil }

    private static var storedRefreshToken: String? {
        Keychain.load(account: refreshAccount)
    }

    private var redirectURI: String {
        // iOS OAuth client redirect: com.googleusercontent.apps.<id>:/oauth2redirect
        "com.googleusercontent.apps.\(Self.clientID!):/oauth2redirect"
    }

    private var urlScheme: String {
        "com.googleusercontent.apps.\(Self.clientID!)"
    }

    // MARK: - Sign in / out (explicit user consent)

    /// Starts the Google sign-in flow. Must be called from the main actor;
    /// presents the system browser sheet for the user to consent.
    public func signIn() async throws {
        guard let clientID = Self.clientID else { throw DriveBackupError.notConfigured }
        let verifier = Self.randomURLSafeBytes(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeBytes(16)
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let authURL = comps.url!
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: urlScheme) { [weak self] url, error in
                self?.authSession = nil
                if let error {
                    cont.resume(throwing: (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                        ? DriveBackupError.authCancelled
                        : DriveBackupError.authFailed(error.localizedDescription))
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: DriveBackupError.authCancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                self.authSession = nil
                cont.resume(throwing: DriveBackupError.authFailed("Could not start browser session."))
            }
        }
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw DriveBackupError.authFailed("Bad callback.") }
        try await exchangeCode(code, verifier: verifier)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        guard let clientID = Self.clientID else { throw DriveBackupError.notConfigured }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        let body: [String: String] = [
            "code": code, "client_id": clientID, "code_verifier": verifier,
            "redirect_uri": redirectURI, "grant_type": "authorization_code",
        ]
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw DriveBackupError.authFailed("Token exchange failed (\(String(data: data, encoding: .utf8) ?? ""))")
        }
        struct TokenResponse: Decodable { var refresh_token: String?; var access_token: String? }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = tokens.refresh_token else {
            throw DriveBackupError.authFailed("No refresh token returned.")
        }
        Keychain.save(refresh, account: Self.refreshAccount)
        // Fetch the account email for display (best effort).
        if let access = tokens.access_token {
            accountEmail = await fetchEmail(accessToken: access)
            if let email = accountEmail { Keychain.save(email, account: Self.emailAccount) }
        }
        isSignedIn = true
    }

    public func signOut() {
        Keychain.delete(account: Self.refreshAccount)
        Keychain.delete(account: Self.emailAccount)
        accountEmail = nil
        isSignedIn = false
    }

    // MARK: - Backup / restore

    /// Uploads the payload to Drive's appDataFolder (creates or overwrites).
    public func backup(_ payload: BackupPayload) async throws -> Date {
        let access = try await accessToken()
        let data = try JSONEncoder().encode(payload)
        let fileID = try await existingFileID(accessToken: access)
        if let fileID {
            // Overwrite existing file content.
            var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw DriveBackupError.networkFailed("Upload failed.")
            }
        } else {
            // Multipart create.
            let boundary = "gw-\(UUID().uuidString)"
            var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            body.append("{\"name\":\"\(Self.backupFileName)\",\"parents\":[\"appDataFolder\"]}".data(using: .utf8)!)
            body.append("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--".data(using: .utf8)!)
            req.httpBody = body
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw DriveBackupError.networkFailed("Upload failed.")
            }
        }
        return Date()
    }

    /// Downloads the backup, or nil when none exists.
    public func restore() async throws -> BackupPayload? {
        let access = try await accessToken()
        guard let fileID = try await existingFileID(accessToken: access) else { return nil }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw DriveBackupError.networkFailed("Download failed.")
        }
        return try JSONDecoder().decode(BackupPayload.self, from: data)
    }

    // MARK: - Private helpers

    private func accessToken() async throws -> String {
        guard let clientID = Self.clientID else { throw DriveBackupError.notConfigured }
        guard let refresh = Self.storedRefreshToken else { throw DriveBackupError.notSignedIn }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        let body = "refresh_token=\(refresh)&client_id=\(clientID)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveBackupError.notSignedIn }
            struct R: Decodable { var access_token: String }
            return try JSONDecoder().decode(R.self, from: data).access_token
        } catch {
            throw DriveBackupError.networkFailed("Token refresh failed.")
        }
    }

    private func existingFileID(accessToken: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "q", value: "name = '\(Self.backupFileName)'"),
            .init(name: "fields", value: "files(id)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw DriveBackupError.networkFailed("Drive query failed.")
        }
        struct List: Decodable { struct F: Decodable { var id: String }; var files: [F] }
        return try JSONDecoder().decode(List.self, from: data).files.first?.id
    }

    private func fetchEmail(accessToken: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any]
        else { return nil }
        return user["emailAddress"] as? String
    }

    private static func randomURLSafeBytes(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleDriveBackup: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
