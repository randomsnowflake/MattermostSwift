import Foundation
@_spi(Testing) import MattermostSwift

// Authentication scenarios.
extension MattermostSwiftCLI {
    static func runLoginTest() async throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["MATTERMOST_MFA_TOKEN"]?.isEmpty == false {
            var withoutCode = environment
            withoutCode.removeValue(forKey: "MATTERMOST_MFA_TOKEN")
            do {
                let unexpected = try await MattermostClient.loginFromEnvironment(withoutCode)
                _ = try await unexpected.client().logoutCurrentSession()
                throw MattermostError.incompleteSync("Expected an MFA challenge without a code.")
            } catch let error as MattermostError where error.isMFARequired {
                print("mfa-challenge: verified")
            }
        }
        let session = try await MattermostClient.loginFromEnvironment(environment)
        let client = try session.client()
        do {
            let user = try await client.currentUser()
            guard user.id == session.user.id else {
                throw MattermostError.incompleteSync("Login and authenticated user do not match.")
            }
            print("token-received: \(!session.token.isEmpty)")
            print("token-source: \(session.tokenSource.rawValue)")
            print("authenticated-user: verified")
        } catch {
            do {
                _ = try await client.logoutCurrentSession()
            } catch {
                fputs("Login test session cleanup failed.\n", stderr)
            }
            throw error
        }
        _ = try await client.logoutCurrentSession()
        print("session-logout: verified")
    }
}
