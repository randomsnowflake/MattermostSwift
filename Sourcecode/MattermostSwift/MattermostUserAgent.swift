import Foundation

enum MattermostUserAgent {
    /// User-Agent sent on every request so the SDK presents as a browser client.
    ///
    /// This is load-bearing, not cosmetic. Mattermost's login flow issues the
    /// `MMAUTHTOKEN` session cookie for browser-like clients, and some edge/WAF
    /// deployments gate requests on the User-Agent. Replacing this with an
    /// SDK-style identifier can silently break cookie-based login, so change it
    /// deliberately and test the login path if you do.
    static let browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    static func applyBrowserUserAgent(to request: inout URLRequest) {
        request.setValue(browser, forHTTPHeaderField: "User-Agent")
    }
}
