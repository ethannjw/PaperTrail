// GoogleAuthService.swift
// Implements OAuth2 Authorization Code Flow with PKCE for Google APIs.
// Tokens are stored in Keychain. Handles refresh automatically.

import Foundation
import UIKit
import Combine
import AuthenticationServices
import CryptoKit

// MARK: - Token Container

struct GoogleToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60) // 60s buffer
    }
}

// MARK: - Service

@MainActor
final class GoogleAuthService: NSObject, ObservableObject {

    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false

    private let scopes = [
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/spreadsheets"
    ]

    private let config = AppConfig.shared
    private var webSession: ASWebAuthenticationSession?
    private var codeVerifier: String = ""

    // MARK: - Lifecycle

    override init() {
        super.init()
        Task { await checkExistingAuth() }
    }

    // MARK: - Public API

    /// Returns a valid access token, refreshing if expired.
    func validAccessToken() async throws -> String {
        if let stored = try loadStoredToken() {
            if !stored.isExpired {
                return stored.accessToken
            }
            if let refresh = stored.refreshToken {
                return try await refreshToken(refresh)
            }
        }
        throw AppError.googleAuthRequired
    }

    /// Starts the OAuth2 web flow.
    func signIn() async throws {
        isLoading = true
        defer { isLoading = false }

        // PKCE
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(verifier: codeVerifier)

        let authURL = buildAuthURL(codeChallenge: codeChallenge)
        let callbackURL = try await presentWebAuthSession(url: authURL)
        let code = try extractCode(from: callbackURL)
        let token = try await exchangeCode(code, verifier: codeVerifier)
        try storeToken(token)
        isAuthenticated = true
    }

    /// Revokes tokens and clears Keychain.
    func signOut() {
        try? KeychainService.delete(key: .googleAccessToken)
        try? KeychainService.delete(key: .googleRefreshToken)
        try? KeychainService.delete(key: .googleTokenExpiry)
        isAuthenticated = false
    }

    // MARK: - Auth URL

    private func buildAuthURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: config.googleClientID),
            URLQueryItem(name: "redirect_uri",          value: config.googleRedirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type",           value: "offline"),
            URLQueryItem(name: "prompt",                value: "consent")
        ]
        return components.url!
    }

    // MARK: - Web Auth Session

    private func presentWebAuthSession(url: URL) async throws -> URL {
        guard let scheme = URL(string: config.googleRedirectURI)?.scheme else {
            throw AppError.googleAuthFailed("Invalid redirect URI scheme")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: AppError.googleAuthFailed(error.localizedDescription))
                } else if let url = callbackURL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AppError.googleAuthFailed("No callback URL"))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            self.webSession = session
            session.start()
        }
    }

    // MARK: - Code Extraction

    private func extractCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            // Check for error
            let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value ?? "Unknown"
            throw AppError.googleAuthFailed("Auth error: \(error)")
        }
        return code
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleToken {
        let body = [
            "code":           code,
            "client_id":      config.googleClientID,
            "redirect_uri":   config.googleRedirectURI,
            "grant_type":     "authorization_code",
            "code_verifier":  verifier
        ]
        return try await requestToken(body: body)
    }

    // MARK: - Token Refresh

    private func refreshToken(_ refreshToken: String) async throws -> String {
        let body = [
            "refresh_token": refreshToken,
            "client_id":     config.googleClientID,
            "grant_type":    "refresh_token"
        ]

        // For refresh, we keep the existing refresh token
        var token = try await requestToken(body: body)
        // Re-use stored refresh token if new one not returned
        if token.refreshToken == nil, let stored = try loadStoredToken() {
            token = GoogleToken(
                accessToken:  token.accessToken,
                refreshToken: stored.refreshToken,
                expiresAt:    token.expiresAt
            )
        }
        try storeToken(token)
        return token.accessToken
    }

    private func requestToken(body: [String: String]) async throws -> GoogleToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.tokenRefreshFailed(errBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let accessToken = json["access_token"] as? String,
              let expiresIn   = json["expires_in"] as? Int
        else { throw AppError.tokenRefreshFailed("Unexpected token response") }

        return GoogleToken(
            accessToken:  accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresAt:    Date().addingTimeInterval(Double(expiresIn))
        )
    }

    // MARK: - Keychain Persistence

    private func storeToken(_ token: GoogleToken) throws {
        try KeychainService.save(token.accessToken, for: .googleAccessToken)
        if let refresh = token.refreshToken {
            try KeychainService.save(refresh, for: .googleRefreshToken)
        }
        let expiry = ISO8601DateFormatter().string(from: token.expiresAt)
        try KeychainService.save(expiry, for: .googleTokenExpiry)
    }

    private func loadStoredToken() throws -> GoogleToken? {
        guard
            let access  = try KeychainService.loadOptional(key: .googleAccessToken),
            let expStr  = try KeychainService.loadOptional(key: .googleTokenExpiry),
            let expiry  = ISO8601DateFormatter().date(from: expStr)
        else { return nil }

        let refresh = try KeychainService.loadOptional(key: .googleRefreshToken)
        return GoogleToken(accessToken: access, refreshToken: refresh, expiresAt: expiry)
    }

    private func checkExistingAuth() async {
        isAuthenticated = (try? loadStoredToken()) != nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first
            else {
                return ASPresentationAnchor()
            }
            return window
        }
    }
}
