import Foundation
import Testing
@testable import MattermostSwift

// MARK: - Redirect credential guard

@Test
func redirectGuardKeepsCredentialsOnlyOnTheServerOrigin() throws {
    func request(_ url: String, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: try #require(URL(string: url)))
        request.httpMethod = method
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        request.setValue("MMAUTHTOKEN=token", forHTTPHeaderField: "Cookie")
        return request
    }
    let source = URL(string: "https://chat.example.com/api/v4/files/f")

    let sameOrigin = MattermostRedirectGuard.redirectRequest(
        try request("https://CHAT.example.com:443/api/v4/files/f/preview"), from: source
    )
    #expect(sameOrigin?.value(forHTTPHeaderField: "Authorization") == "Bearer token")

    let crossHost = MattermostRedirectGuard.redirectRequest(
        try request("https://cdn.example.net/f"), from: source
    )
    #expect(crossHost?.url?.host == "cdn.example.net")
    #expect(crossHost?.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(crossHost?.value(forHTTPHeaderField: "Cookie") == nil)

    let crossPort = MattermostRedirectGuard.redirectRequest(
        try request("https://chat.example.com:8443/api/v4/files/f"), from: source
    )
    #expect(crossPort?.value(forHTTPHeaderField: "Authorization") == nil)

    #expect(MattermostRedirectGuard.redirectRequest(
        try request("http://chat.example.com/api/v4/files/f"), from: source
    ) == nil)
    #expect(MattermostRedirectGuard.redirectRequest(
        try request("https://evil.example.net/login", method: "POST"), from: source
    ) == nil)
}

@Test
func restRequestsDoNotFollowADowngradeRedirectWithTheToken() async throws {
    let targetHits = MattermostRequestLog()
    let session = await MattermostTestSupport.urlSession { request in
        targetHits.append("\(request.url?.absoluteString ?? "") auth=\(request.value(forHTTPHeaderField: "Authorization") ?? "nil")")
        return try MattermostTestSupport.response(statusCode: 200, body: Data("{}".utf8), request: request)
    }
    MattermostRedirectingURLProtocol.target = try #require(URL(string: "http://mattermost.example.com/api/v4/users/me"))
    let configuration = session.configuration
    configuration.protocolClasses = [MattermostRedirectingURLProtocol.self, MattermostMockURLProtocol.self]
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: URLSession(configuration: configuration)
    )

    await #expect(throws: (any Error).self) {
        _ = try await client.currentUser()
    }
    #expect(targetHits.values.isEmpty)
}

/// Answers every HTTPS request with a 302 to `target`; plain-HTTP requests fall through to
/// the mock handler so a followed redirect would be observable.
private final class MattermostRedirectingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var target: URL?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let target = Self.target,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 302,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Location": target.absoluteString]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var redirected = request
        redirected.url = target
        client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - WebSocket authentication failures

@Test
func rejectedWebSocketUpgradeIsTerminalWithoutProbing() async throws {
    let probes = MattermostRequestLog()
    for status in [401, 403] {
        let error = await MattermostLiveEventStream.authenticationFailure(
            for: URLError(.badServerResponse),
            upgradeStatusCode: status,
            probe: { probes.append("probe") }
        )
        #expect(error?.isUnauthorized == (status == 401))
        #expect(error?.isForbidden == (status == 403))
    }
    #expect(probes.values.isEmpty)
}

@Test
func silentHandshakeCloseIsTerminalOnlyWhenRESTRejectsTheToken() async throws {
    let closed = MattermostError.transportFailure("Mattermost WebSocket closed before authentication completed.")

    let revoked = await MattermostLiveEventStream.authenticationFailure(
        for: closed,
        upgradeStatusCode: 101,
        probe: { throw MattermostError.httpStatus(code: 401, message: nil, apiError: nil) }
    )
    #expect(revoked?.isUnauthorized == true)

    let healthy = await MattermostLiveEventStream.authenticationFailure(
        for: closed, upgradeStatusCode: 101, probe: {}
    )
    #expect(healthy == nil)

    let offline = await MattermostLiveEventStream.authenticationFailure(
        for: closed,
        upgradeStatusCode: 101,
        probe: { throw MattermostError.transportFailure("offline") }
    )
    #expect(offline == nil)

    let probes = MattermostRequestLog()
    let neverUpgraded = await MattermostLiveEventStream.authenticationFailure(
        for: URLError(.timedOut), upgradeStatusCode: nil, probe: { probes.append("probe") }
    )
    #expect(neverUpgraded == nil)
    #expect(probes.values.isEmpty)

    let cancelled = await MattermostLiveEventStream.authenticationFailure(
        for: CancellationError(), upgradeStatusCode: 401, probe: nil
    )
    #expect(cancelled == nil)
}

@Test
func clientLiveEventStreamProbesTheCurrentUser() async throws {
    let requests = MattermostRequestLog()
    let client = try MattermostClient(
        serverURL: try #require(URL(string: "https://mattermost.example.com")),
        token: "token",
        urlSession: await MattermostTestSupport.urlSession { request in
            requests.append(request.url?.path ?? "")
            return try MattermostTestSupport.response(statusCode: 401, body: Data("{}".utf8), request: request)
        }
    )
    let probe = try #require(client.liveEventStream().authenticationProbe)

    await #expect(throws: MattermostError.self) { try await probe() }
    #expect(requests.values == ["/api/v4/users/me"])
}
