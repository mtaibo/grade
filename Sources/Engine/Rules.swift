/// A minimum a node's grade must reach, with what happens when it isn't met.
///
/// Can live on any node. `capAt` caps the *parent's* result, matching guides where
/// e.g. failing the final exam caps the whole subject at 4.5 regardless of the rest.
public struct Minimum: Sendable, Equatable {
    public enum Consequence: Sendable, Equatable {
        case doesNotAverage
        case capAt(Double)
        case fails
    }

    public var threshold: Double
    public var consequence: Consequence

    public init(threshold: Double, consequence: Consequence) {
        self.threshold = threshold
        self.consequence = consequence
    }
}

/// How a node's grade carries over to the extraordinary session or beyond.
public enum Recovery: Sendable, Equatable {
    case recoverableInExtraordinary
    case notRecoverable
    case partiallyRecoverableInFinal
    case savedForExtraordinary
    case savedForNextYear
}
