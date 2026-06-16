import Foundation

enum MattermostUserAgent {
    static let browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    static func applyBrowserUserAgent(to request: inout URLRequest) {
        request.setValue(browser, forHTTPHeaderField: "User-Agent")
    }
}
