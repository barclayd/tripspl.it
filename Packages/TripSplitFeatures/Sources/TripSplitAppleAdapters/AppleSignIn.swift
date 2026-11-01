import AuthenticationServices
import CryptoKit
import Foundation
import TripSplitDomain
import TripSplitSync

/// Translates Apple's platform credentials at the UI boundary.
@MainActor public enum AppleSignIn {
  public static func configure(_ request: ASAuthorizationAppleIDRequest, challenge: AuthChallenge?)
  {
    request.requestedScopes = [.fullName, .email]
    if let challenge {
      request.nonce = SHA256.hash(data: Data(challenge.nonce.utf8)).map {
        String(format: "%02x", $0)
      }.joined()
    }
  }
  public static func complete(_ result: Result<ASAuthorization, Error>, sync: SyncCoordinator) async
  {
    do {
      let authorization = try result.get()
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = credential.identityToken,
        let token = String(data: tokenData, encoding: .utf8),
        let codeData = credential.authorizationCode,
        let code = String(data: codeData, encoding: .utf8)
      else {
        throw ServiceError(
          code: "apple", message: "Apple didn’t return a complete sign-in response. Try again.")
      }
      let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
      await sync.completeApple(identityToken: token, authorizationCode: code, displayName: name)
    } catch {
      sync.message = error.localizedDescription
      await sync.prepareApple()
    }
  }
}
