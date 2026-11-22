import Foundation

/// iOS 17 replacement for `Synchronization.Mutex` (iOS 18).
///
/// The call sites only need a value with an exclusive `withLock` entry point, so
/// an `NSLock`-backed box keeps the same shape without a platform floor.
nonisolated final class AALockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}
