import Foundation

public extension Date {
    /// Creates a date from a Mattermost epoch timestamp expressed in milliseconds.
    init(mattermostMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(mattermostMilliseconds) / 1_000)
    }

    /// The date as a Mattermost epoch timestamp in milliseconds.
    ///
    /// Sub-millisecond precision is rounded to the nearest millisecond.
    var mattermostMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }
}
