import Foundation

/// Backoff controls for reconnecting Mattermost WebSocket event streams.
public struct MattermostLiveEventReconnectPolicy: Equatable, Sendable {
    // Keep a margin below `Int.max`: converting a rounded `Double(Int.max)` can
    // otherwise cross the signed-integer boundary on some architectures.
    private static let maximumDelayMilliseconds = Int.max / 2
    public static let `default` = MattermostLiveEventReconnectPolicy()

    public static let disabled = MattermostLiveEventReconnectPolicy(maxRetries: 0)

    public let initialDelay: Duration
    public let maximumDelay: Duration
    public let multiplier: Double
    public let maxRetries: Int?
    public let reconnectAfterCleanClose: Bool

    public init(
        initialDelay: Duration = .seconds(1),
        maximumDelay: Duration = .seconds(60),
        multiplier: Double = 2,
        maxRetries: Int? = nil,
        reconnectAfterCleanClose: Bool = true
    ) {
        let initialMilliseconds = Self.normalizedMilliseconds(
            initialDelay,
            fallback: 1_000
        )
        let maximumMilliseconds = max(
            initialMilliseconds,
            Self.normalizedMilliseconds(maximumDelay, fallback: 60_000)
        )
        self.initialDelay = .milliseconds(initialMilliseconds)
        self.maximumDelay = .milliseconds(maximumMilliseconds)
        self.multiplier = multiplier.isFinite && multiplier >= 1 ? multiplier : 1
        self.maxRetries = maxRetries.map { max(0, $0) }
        self.reconnectAfterCleanClose = reconnectAfterCleanClose
    }

    public func canRetry(attempt: Int) -> Bool {
        guard let maxRetries else {
            return true
        }
        return attempt < maxRetries
    }

    /// Returns a full-jitter reconnect delay from zero through the capped exponential backoff.
    public func delay(for attempt: Int) -> Duration {
        delay(for: attempt, jitterFraction: .random(in: 0...1))
    }

    func delay(for attempt: Int, jitterFraction: Double) -> Duration {
        let exponent = pow(multiplier, Double(max(0, attempt)))
        let initialMilliseconds = Self.milliseconds(from: initialDelay)
        let maximumMilliseconds = Self.milliseconds(from: maximumDelay)
        let computedMilliseconds = Double(initialMilliseconds) * exponent
        // Cap in the integer domain: Double cannot represent every millisecond value near
        // the saturating maximum, and rounding there would drift the cap by a millisecond.
        let baseMilliseconds: Int
        if computedMilliseconds.isFinite,
           computedMilliseconds < Double(maximumMilliseconds) {
            baseMilliseconds = max(0, Int(computedMilliseconds))
        } else {
            baseMilliseconds = maximumMilliseconds
        }
        let normalizedJitter = jitterFraction.isFinite
            ? min(1, max(0, jitterFraction))
            : 0
        let jitteredMilliseconds = normalizedJitter >= 1
            ? baseMilliseconds
            : max(0, Int(Double(baseMilliseconds) * normalizedJitter))
        return .milliseconds(min(
            Self.maximumDelayMilliseconds,
            jitteredMilliseconds
        ))
    }

    @available(*, deprecated, message: "Use init(initialDelay:maximumDelay:multiplier:maxRetries:reconnectAfterCleanClose:)")
    public init(
        initialDelaySeconds: Double,
        maxDelaySeconds: Double = 60,
        multiplier: Double = 2,
        maxRetries: Int? = nil,
        reconnectAfterCleanClose: Bool = true
    ) {
        self.init(
            initialDelay: Self.duration(seconds: initialDelaySeconds, fallback: 1),
            maximumDelay: Self.duration(seconds: maxDelaySeconds, fallback: 60),
            multiplier: multiplier,
            maxRetries: maxRetries,
            reconnectAfterCleanClose: reconnectAfterCleanClose
        )
    }

    @available(*, deprecated, message: "Use init(initialDelay:maximumDelay:multiplier:maxRetries:reconnectAfterCleanClose:)")
    public init(
        maxDelaySeconds: Double,
        multiplier: Double = 2,
        maxRetries: Int? = nil,
        reconnectAfterCleanClose: Bool = true
    ) {
        self.init(
            initialDelay: .seconds(1),
            maximumDelay: Self.duration(seconds: maxDelaySeconds, fallback: 60),
            multiplier: multiplier,
            maxRetries: maxRetries,
            reconnectAfterCleanClose: reconnectAfterCleanClose
        )
    }

    @available(*, deprecated, renamed: "initialDelay")
    public var initialDelaySeconds: Double {
        Double(Self.milliseconds(from: initialDelay)) / 1_000
    }

    @available(*, deprecated, renamed: "maximumDelay")
    public var maxDelaySeconds: Double {
        Double(Self.milliseconds(from: maximumDelay)) / 1_000
    }

    private static func normalizedMilliseconds(_ value: Duration, fallback: Int) -> Int {
        let components = value.components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            return fallback
        }
        return milliseconds(from: value)
    }

    private static func milliseconds(from value: Duration) -> Int {
        let components = value.components
        guard components.seconds > 0 || components.attoseconds > 0 else {
            return 0
        }
        // Saturate on the exact millisecond cap. Clamping the seconds first and then
        // multiplying would round the cap down to a whole second.
        guard components.seconds < Int64(maximumDelayMilliseconds / 1_000) else {
            return maximumDelayMilliseconds
        }
        let wholeMilliseconds = Int(components.seconds) * 1_000
        let fractionalMilliseconds = max(
            0,
            Int(components.attoseconds / 1_000_000_000_000_000)
        )
        return min(maximumDelayMilliseconds, wholeMilliseconds + fractionalMilliseconds)
    }

    private static func duration(seconds: Double, fallback: Double) -> Duration {
        guard seconds.isFinite, seconds >= 0 else {
            return .milliseconds(Int(fallback * 1_000))
        }
        let cappedSeconds = min(
            seconds,
            Double(maximumDelayMilliseconds) / 1_000
        )
        let milliseconds = Int(cappedSeconds * 1_000)
        return .milliseconds(milliseconds)
    }
}
