import Testing
@testable import MattermostSwift

@Test(arguments: [
    ("/api/v4/", "api/v4/"),
    ("///p", "p"),
    ("", ""),
    ("no-slash", "no-slash"),
])
func stripsLeadingSlashes(input: String, expected: String) {
    #expect(input.mattermostTrimmingLeadingSlashes == expected)
}

@Test(arguments: [
    ("/api/v4/", "/api/v4"),
    ("p///", "p"),
    ("", ""),
    ("no-slash", "no-slash"),
])
func stripsTrailingSlashes(input: String, expected: String) {
    #expect(input.mattermostTrimmingTrailingSlashes == expected)
}
