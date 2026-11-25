import Foundation

/// One verifiable statement about the product. The name is a spec
/// sentence — "when … returns …" — never a test-method identifier.
public struct Check: Sendable {
    public let name: String
    public let body: @Sendable () throws -> Void

    public init(_ name: String, _ body: @escaping @Sendable () throws -> Void) {
        self.name = name
        self.body = body
    }
}

public struct CheckFailure: Error, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}

public func expect(_ condition: @autoclosure () -> Bool, _ message: String = "") throws {
    if !condition() { throw CheckFailure(message: message.isEmpty ? "expectation failed" : message) }
}

public func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    try expect(actual == expected, "\(actual) != \(expected)")
}

/// Runs every check, prints `ok`/`not ok` TAP-ish lines, returns the
/// failure count so `slChecks` can exit nonzero.
public enum CheckRunner {
    public static func run(_ checks: [Check]) -> Int {
        var failures = 0
        for (i, check) in checks.enumerated() {
            do {
                try check.body()
                print("ok \(i + 1) - \(check.name)")
            } catch {
                failures += 1
                print("not ok \(i + 1) - \(check.name) — \(error)")
            }
        }
        print("\(checks.count - failures)/\(checks.count) checks passed")
        return failures
    }
}
