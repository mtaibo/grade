import Foundation

/// Why a formula typed by hand couldn't be read, in words the person typing it can act on.
public struct FormulaParseError: Error, Equatable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

extension Expression {
    /// Variable names in the order they first appear, so "P + C + …" lists P, then C.
    public var variableOrder: [String] {
        var seen: [String] = []
        func visit(_ expression: Expression) {
            switch expression {
            case .constant: break
            case .variable(let name): if !seen.contains(name) { seen.append(name) }
            case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b),
                 .divide(let a, let b), .min(let a, let b), .max(let a, let b):
                visit(a); visit(b)
            case .ifGreaterOrEqual(let lhs, let rhs, let then, let otherwise):
                visit(lhs); visit(rhs); visit(then); visit(otherwise)
            }
        }
        visit(self)
        return seen
    }

    /// The same expression with one variable renamed everywhere it's used.
    public func renamingVariable(_ old: String, to new: String) -> Expression {
        func go(_ e: Expression) -> Expression { e.renamingVariable(old, to: new) }
        switch self {
        case .constant: return self
        case .variable(let name): return .variable(name == old ? new : name)
        case .add(let a, let b): return .add(go(a), go(b))
        case .subtract(let a, let b): return .subtract(go(a), go(b))
        case .multiply(let a, let b): return .multiply(go(a), go(b))
        case .divide(let a, let b): return .divide(go(a), go(b))
        case .min(let a, let b): return .min(go(a), go(b))
        case .max(let a, let b): return .max(go(a), go(b))
        case .ifGreaterOrEqual(let lhs, let rhs, let then, let otherwise):
            return .ifGreaterOrEqual(lhs: go(lhs), rhs: go(rhs), then: go(then), otherwise: go(otherwise))
        }
    }

    // MARK: Printing

    /// The formula as text that `parse` reads back: `0,1 * (8 - C) * F`, `min(a; b)`,
    /// `si(E >= 4; entonces; si no)`. Decimals use a comma, arguments are separated by `;`.
    public var source: String {
        func precedence(_ e: Expression) -> Int {
            switch e {
            case .add, .subtract: 1
            case .multiply, .divide: 2
            default: 3
            }
        }
        func binary(_ lhs: Expression, _ op: String, _ rhs: Expression, _ level: Int) -> String {
            let left = precedence(lhs) < level ? "(\(lhs.source))" : lhs.source
            let right = precedence(rhs) <= level ? "(\(rhs.source))" : rhs.source
            return "\(left) \(op) \(right)"
        }
        switch self {
        case .constant(let value):
            let rounded = (value * 1_000_000).rounded() / 1_000_000
            if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
            return String(rounded).replacingOccurrences(of: ".", with: ",")
        case .variable(let name): return name
        case .add(let a, let b): return binary(a, "+", b, 1)
        case .subtract(let a, let b): return binary(a, "-", b, 1)
        case .multiply(let a, let b): return binary(a, "*", b, 2)
        case .divide(let a, let b): return binary(a, "/", b, 2)
        case .min(let a, let b): return "min(\(a.source); \(b.source))"
        case .max(let a, let b): return "max(\(a.source); \(b.source))"
        case .ifGreaterOrEqual(let lhs, let rhs, let then, let otherwise):
            return "si(\(lhs.source) >= \(rhs.source); \(then.source); \(otherwise.source))"
        }
    }

    // MARK: Parsing

    /// Reads a formula typed by hand. Numbers take a comma or a point, `+ - * /` and parentheses
    /// work as usual, `min(a; b)` / `max(a; b)` take two arguments, and `si(a >= b; x; y)` picks `x`
    /// when `a >= b` and `y` otherwise (`<=` works too). Only the names in `variables` are allowed.
    public static func parse(_ text: String, variables: Set<String>) throws -> Expression {
        var parser = FormulaParser(characters: Array(text), variables: variables)
        let expression = try parser.parseExpression()
        parser.skipSpaces()
        if let next = parser.peek {
            throw FormulaParseError(message: parser.unexpectedMessage(next))
        }
        return expression
    }
}

private struct FormulaParser {
    let characters: [Character]
    let variables: Set<String>
    var index = 0

    init(characters: [Character], variables: Set<String>) {
        self.characters = characters
        self.variables = variables
    }

    var peek: Character? { index < characters.count ? characters[index] : nil }

    mutating func skipSpaces() {
        while let c = peek, c.isWhitespace { index += 1 }
    }

    func unexpectedMessage(_ c: Character) -> String {
        switch c {
        case ",": "Separa los argumentos con «;» (la coma es para los decimales)."
        case ")": "Sobra un paréntesis de cierre."
        case ">", "<": "Para comparar usa «>=» o «<=»."
        default: "No entiendo «\(c)»."
        }
    }

    mutating func parseExpression() throws -> Expression {
        var result = try parseTerm()
        while true {
            skipSpaces()
            guard let c = peek, "+-−".contains(c) else { return result }
            index += 1
            let rhs = try parseTerm()
            result = c == "+" ? .add(result, rhs) : .subtract(result, rhs)
        }
    }

    mutating func parseTerm() throws -> Expression {
        var result = try parseUnary()
        while true {
            skipSpaces()
            guard let c = peek, "*/·×÷".contains(c) else { return result }
            index += 1
            let rhs = try parseUnary()
            result = "*·×".contains(c) ? .multiply(result, rhs) : .divide(result, rhs)
        }
    }

    mutating func parseUnary() throws -> Expression {
        skipSpaces()
        if let c = peek, c == "-" || c == "−" {
            index += 1
            return .subtract(.constant(0), try parseUnary())
        }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> Expression {
        skipSpaces()
        guard let c = peek else { throw FormulaParseError(message: "La fórmula termina antes de tiempo.") }
        if c == "(" {
            index += 1
            let inner = try parseExpression()
            skipSpaces()
            guard peek == ")" else { throw FormulaParseError(message: "Falta cerrar un paréntesis.") }
            index += 1
            return inner
        }
        if c.isNumber || c == "." || c == "," {
            return try parseNumber()
        }
        if c.isLetter || c == "_" {
            return try parseName()
        }
        throw FormulaParseError(message: unexpectedMessage(c))
    }

    mutating func parseNumber() throws -> Expression {
        var text = ""
        var sawSeparator = false
        while let c = peek {
            if c.isNumber, c.isASCII {
                text.append(c)
            } else if (c == "." || c == ","), !sawSeparator {
                sawSeparator = true
                text.append(".")
            } else {
                break
            }
            index += 1
        }
        guard let value = Double(text) else { throw FormulaParseError(message: "«\(text)» no es un número.") }
        return .constant(value)
    }

    mutating func parseName() throws -> Expression {
        var name = ""
        while let c = peek, c.isLetter || c.isNumber || c == "_" {
            name.append(c)
            index += 1
        }
        skipSpaces()
        if peek == "(" {
            index += 1
            return try parseCall(name)
        }
        guard variables.contains(name) else {
            throw FormulaParseError(message: "«\(name)» no es ninguna de tus variables.")
        }
        return .variable(name)
    }

    mutating func parseArguments() throws -> [Expression] {
        var arguments: [Expression] = []
        skipSpaces()
        if peek == ")" {
            index += 1
            return arguments
        }
        while true {
            arguments.append(try parseExpression())
            skipSpaces()
            if peek == ";" {
                index += 1
            } else if peek == ")" {
                index += 1
                return arguments
            } else if let c = peek {
                throw FormulaParseError(message: unexpectedMessage(c))
            } else {
                throw FormulaParseError(message: "Falta cerrar un paréntesis.")
            }
        }
    }

    mutating func parseCall(_ name: String) throws -> Expression {
        switch name.lowercased() {
        case "min", "mín":
            let args = try parseArguments()
            guard args.count == 2 else { throw FormulaParseError(message: "«\(name)» necesita dos valores separados por «;».") }
            return .min(args[0], args[1])
        case "max", "máx":
            let args = try parseArguments()
            guard args.count == 2 else { throw FormulaParseError(message: "«\(name)» necesita dos valores separados por «;».") }
            return .max(args[0], args[1])
        case "si", "if":
            let lhs = try parseExpression()
            skipSpaces()
            let isLessOrEqual: Bool
            if match(">=") || match("≥") {
                isLessOrEqual = false
            } else if match("<=") || match("≤") {
                isLessOrEqual = true
            } else {
                throw FormulaParseError(message: "«si» empieza con una comparación: «si(E >= 4; entonces; si no)».")
            }
            let rhs = try parseExpression()
            skipSpaces()
            guard peek == ";" else { throw FormulaParseError(message: "«si» necesita tres partes separadas por «;».") }
            index += 1
            let rest = try parseArguments()
            guard rest.count == 2 else { throw FormulaParseError(message: "«si» necesita tres partes separadas por «;».") }
            return isLessOrEqual
                ? .ifGreaterOrEqual(lhs: rhs, rhs: lhs, then: rest[0], otherwise: rest[1])
                : .ifGreaterOrEqual(lhs: lhs, rhs: rhs, then: rest[0], otherwise: rest[1])
        default:
            throw FormulaParseError(message: "No conozco la función «\(name)». Puedes usar min, max y si.")
        }
    }

    mutating func match(_ token: String) -> Bool {
        let chars = Array(token)
        guard index + chars.count <= characters.count, Array(characters[index..<index + chars.count]) == chars else { return false }
        index += chars.count
        return true
    }
}

extension Formula {
    /// The most this variable can add to the final grade (in points out of 10): what it gives on its
    /// own with everything else at zero, or what the total loses without it, whichever is larger —
    /// and its own maximum if the formula never lets it count by itself. What a guide would call
    /// "hasta el N %".
    public func maxShare(of key: String) -> Double {
        let maxima = variables.mapValues(\.scaleMax)
        func value(_ values: [String: Double]) -> Double {
            let result = expression.evaluate(values)
            return result.isFinite ? result : 0
        }
        guard maxima[key] != nil else { return 0 }
        var alone = maxima.mapValues { _ in 0.0 }
        alone[key] = maxima[key]
        var without = maxima
        without[key] = 0
        let share = Swift.max(value(alone), value(maxima) - value(without))
        return share > 0 ? share : maxima[key] ?? 0
    }
}
