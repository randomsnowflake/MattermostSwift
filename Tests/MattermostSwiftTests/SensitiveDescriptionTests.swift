import Foundation
import Testing
@testable import MattermostSwift

private let sensitiveDescriptionToken = "secret-token-that-must-not-appear"

@Test
func sessionDescriptionsRedactBearerTokenWithoutChangingEquality() {
    let user = MattermostUser(
        id: "user-id",
        username: "alice",
        email: nil,
        firstName: nil,
        lastName: nil,
        nickname: nil,
        position: nil,
        locale: nil,
        timezone: nil,
        lastPictureUpdate: nil
    )
    let session = MattermostSession(
        user: user,
        token: sensitiveDescriptionToken,
        tokenSource: .authCookie
    )

    #expect(!String(describing: session).contains(sensitiveDescriptionToken))
    #expect(!String(reflecting: session).contains(sensitiveDescriptionToken))
    #expect(String(describing: session).contains("<redacted>"))
    #expect(session == MattermostSession(
        user: user,
        token: sensitiveDescriptionToken,
        tokenSource: .authCookie
    ))
    #expect(session != MattermostSession(
        user: user,
        token: "different-token",
        tokenSource: .authCookie
    ))
}

@Test
func authenticationDescriptionsRedactBearerTokenWithoutChangingEquality() {
    let authentication = MattermostAuthentication.bearerToken(sensitiveDescriptionToken)

    #expect(!String(describing: authentication).contains(sensitiveDescriptionToken))
    #expect(!String(reflecting: authentication).contains(sensitiveDescriptionToken))
    #expect(String(describing: authentication).contains("<redacted>"))
    #expect(authentication == .bearerToken(sensitiveDescriptionToken))
    #expect(authentication != .bearerToken("different-token"))
}

@Test
func configurationDescriptionsRedactBearerToken() throws {
    let configuration = try MattermostConfiguration(
        serverURL: #require(URL(string: "https://mattermost.example.com")),
        authentication: .bearerToken(sensitiveDescriptionToken)
    )

    #expect(!String(describing: configuration).contains(sensitiveDescriptionToken))
    #expect(!String(reflecting: configuration).contains(sensitiveDescriptionToken))
    #expect(String(describing: configuration).contains("<redacted>"))
}
