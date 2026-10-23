/// An arithmetic formula over named variables.
///
/// This is how a `Formula` node stops being inert data: it's the general shape behind "the final
/// exam's weight varies continuously with another grade" (Estadística, Matemática Discreta — see
/// `docs/modelo.md`), general enough to not force those guides into `Group`'s fixed weights or
/// `Alternatives`'s discrete branches.
public indirect enum Expression: Sendable, Equatable {
    case constant(Double)
    case variable(String)
    case add(Expression, Expression)
    case subtract(Expression, Expression)
    case multiply(Expression, Expression)
    case divide(Expression, Expression)
    case min(Expression, Expression)
    case max(Expression, Expression)
    /// `lhs >= rhs ? then : otherwise` — the one conditional shape the reference guides need,
    /// e.g. "si E >= 4, F = N; si no, F = min(N, 4.5)".
    case ifGreaterOrEqual(lhs: Expression, rhs: Expression, then: Expression, otherwise: Expression)

    public func evaluate(_ variables: [String: Double]) -> Double {
        switch self {
        case .constant(let value):
            return value
        case .variable(let name):
            guard let value = variables[name] else {
                preconditionFailure("missing value for variable \"\(name)\"")
            }
            return value
        case .add(let lhs, let rhs):
            return lhs.evaluate(variables) + rhs.evaluate(variables)
        case .subtract(let lhs, let rhs):
            return lhs.evaluate(variables) - rhs.evaluate(variables)
        case .multiply(let lhs, let rhs):
            return lhs.evaluate(variables) * rhs.evaluate(variables)
        case .divide(let lhs, let rhs):
            return lhs.evaluate(variables) / rhs.evaluate(variables)
        case .min(let lhs, let rhs):
            return Swift.min(lhs.evaluate(variables), rhs.evaluate(variables))
        case .max(let lhs, let rhs):
            return Swift.max(lhs.evaluate(variables), rhs.evaluate(variables))
        case .ifGreaterOrEqual(let lhs, let rhs, let then, let otherwise):
            return lhs.evaluate(variables) >= rhs.evaluate(variables)
                ? then.evaluate(variables)
                : otherwise.evaluate(variables)
        }
    }
}
