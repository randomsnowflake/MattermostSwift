import Foundation
import Testing
@testable import MattermostSwift

private func config(_ json: String) throws -> MattermostClientConfig {
    try JSONDecoder().decode(MattermostClientConfig.self, from: Data(json.utf8))
}

@Test
func ssoProvidersFollowServerSwitches() throws {
    // Licensed v11 / pre-v11 servers send the GitLab keys explicitly.
    #expect(try config(#"{"EnableSignUpWithGitLab":"false"}"#).ssoProviders == [])
    #expect(try config(#"{"EnableSignUpWithGitLab":"true","GitLabButtonText":"CERN SSO"}"#).ssoProviders == [.gitlab])
    #expect(try config("""
    {"EnableSignUpWithGitLab":"false","EnableSignUpWithGoogle":"true","EnableSignUpWithOffice365":"false",
     "EnableSignUpWithOpenId":"true","EnableSaml":"true"}
    """).ssoProviders == [.google, .openid, .saml])
    #expect(try config(#"{"EnableSignUpWithGitLab":"true"}"#).gitLabButtonText == nil)
}

@Test
func unlicensedServerWithoutGitLabKeysStillOffersGitLab() throws {
    // Live 11.11.3 Team Edition with GitLab on: the keys are absent, the others are "false".
    let unlicensed = try config(#"{"EnableSignUpWithGoogle":"false","EnableSignUpWithOpenId":"false","EnableSaml":"false"}"#)
    #expect(unlicensed.ssoProviders == [.gitlab])
}

@Test
func mobileLoginURLsMatchServerRoutes() {
    let server = URL(string: "https://chat.example.com/mm")!
    #expect(MattermostSSOProvider.gitlab.mobileLoginURL(serverURL: server).absoluteString
        == "https://chat.example.com/mm/oauth/gitlab/mobile_login?redirect_to=mmauth://callback")
    #expect(MattermostSSOProvider.saml.mobileLoginURL(serverURL: server).absoluteString
        == "https://chat.example.com/mm/login/sso/saml?action=mobile&redirect_to=mmauth://callback")
}

@Test
func ssoCallbackCarriesTokenCSRFAndServer() throws {
    let token = MattermostSSOCallback.tokenParameter
    let callback = try MattermostSSOCallback(url: URL(string:
        "mmauth://callback?\(token)=tok123&MMCSRF=csrf9&srv=https%3A%2F%2Fchat.example.com")!)
    #expect(callback.token == "tok123")
    #expect(callback.csrf == "csrf9")
    #expect(callback.serverURL == "https://chat.example.com")

    let withoutServer = try MattermostSSOCallback(url: URL(string: "mmauth://callback?\(token)=t&srv=")!)
    #expect(withoutServer.serverURL == nil)
}

@Test
func ssoCallbackWithoutTokenIsRejected() {
    let token = MattermostSSOCallback.tokenParameter
    for raw in [
        "mmauth://callback?login_code=abc",
        "mmauth://callback?\(token)=",
        "mmauth://callback",
        "https://evil.example.com/callback?\(token)=t",
    ] {
        #expect(throws: MattermostError.missingAuthenticationToken) {
            try MattermostSSOCallback(url: URL(string: raw)!)
        }
    }
}

@Test
func clientConfigLoadsWithoutAuthenticationBeforeSignIn() async throws {
    let session = await MattermostTestSupport.urlSession { request in
        #expect(request.url?.absoluteString == "https://chat.example.com/api/v4/config/client")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = Data(#"{"EnableSignUpWithGoogle":"true","EnableSaml":"false"}"#.utf8)
        return try MattermostTestSupport.response(statusCode: 200, body: body, request: request)
    }

    let config = try await MattermostClient.clientConfig(serverURL: URL(string: "https://chat.example.com")!, urlSession: session)

    // GitLab keys absent (unlicensed v11) still count as "maybe GitLab".
    #expect(config.ssoProviders == [.gitlab, .google])
}

@Test
func clientConfigRefusesPlainHTTPUnlessAllowed() async throws {
    await #expect(throws: (any Error).self) {
        _ = try await MattermostClient.clientConfig(serverURL: URL(string: "http://chat.example.com")!)
    }
}
