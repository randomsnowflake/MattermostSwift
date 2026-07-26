# Authentication

Create a client with a host-owned token or exchange a username and password for a session token.

## Use a Personal Access Token

Use a personal access token when the host app already owns secure credential storage:

```swift
import Foundation
import MattermostSwift

let serverURL = URL(string: "https://mattermost.example.com")!
let client = try MattermostClient(
    serverURL: serverURL,
    token: "personal-access-token"
)

let me = try await client.currentUser()
```

The SDK uses the token for bearer authentication but doesn't write it to Keychain, SwiftData, or
another persistent store.

## Log In With a Password

On deployments that permit password login, request a session and create a client from it:

```swift
let session = try await MattermostClient.login(
    serverURL: serverURL,
    loginID: "user@example.com",
    password: "password"
)

let client = try session.client(serverURL: serverURL)
print(session.tokenSource)
```

``MattermostSession/tokenSource`` identifies whether Mattermost returned the documented `Token`
response header or its browser-compatible `MMAUTHTOKEN` cookie. The login request sends
Mattermost's web-client `X-Requested-With: XMLHttpRequest` header, but the SDK returns only
bearer-capable session state and doesn't retain the password or cookie.

Store the returned token using the host app's security policy. To end a password-login session,
attempt remote cleanup and discard the local token even if cleanup fails:

```swift
do {
    try await client.logoutCurrentSession()
} catch {
    // Continue deleting the locally stored token.
}
```

Personal access tokens may not be accepted by the logout endpoint.

## Load Development Credentials

Command-line tools and local tests can use environment variables:

```sh
export MATTERMOST_URL="https://mattermost.example.com"
export MATTERMOST_TOKEN="personal-access-token"
```

```swift
let client = try MattermostClient.liveFromEnvironment()
```

Don't bundle environment credentials into an app or commit them to source control.

## See Also

- <doc:ErrorHandling>
- ``MattermostSession``
- ``MattermostAuthentication``
