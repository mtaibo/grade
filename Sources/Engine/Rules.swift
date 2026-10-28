/// A minimum a node's grade must reach, with what happens when it isn't met.
///
/// Can live on any node. `fails`, `capAt` and `sendsToExtraordinary` act on the whole subject;
/// `voids` and `doesNotAverage` only on the node itself, inside its parent.
public struct Minimum: Sendable, Equatable, Codable {
    public enum Consequence: Sendable, Equatable, Codable {
        /// The node is left out of its parent's average and the rest share out its weight
        /// ("no hace media").
        case doesNotAverage
        /// The final grade can't go above this, whatever the rest ("no pasa de un 4,5").
        case capAt(Double)
        /// The subject is failed, whatever the average.
        case fails
        /// The node counts as a 0 ("se anulan las prácticas").
        case voids
        /// The ordinary sitting is failed and everything is played in the extraordinary one, where
        /// this minimum no longer applies.
        case sendsToExtraordinary
    }

    public var threshold: Double
    public var consequence: Consequence

    public init(threshold: Double, consequence: Consequence) {
        self.threshold = threshold
        self.consequence = consequence
    }
}

/// How a node's grade carries over to the extraordinary session or beyond.
public enum Recovery: Sendable, Equatable, Codable {
    case recoverableInExtraordinary
    case notRecoverable
    case partiallyRecoverableInFinal
    case savedForExtraordinary
    case savedForNextYear
}
