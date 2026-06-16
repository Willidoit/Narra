import Foundation

func runWithTimeout<T: Sendable>(
    timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async -> T? {
    await withTaskGroup(of: TimeoutOutcome<T>.self) { group in
        group.addTask {
            do {
                return .value(try await operation())
            } catch {
                return .fallback
            }
        }

        group.addTask {
            _ = try? await Task.sleep(for: timeout)
            return .fallback
        }

        let firstResult = await group.next() ?? .fallback
        group.cancelAll()

        switch firstResult {
        case .value(let value):
            return value
        case .fallback:
            return nil
        }
    }
}

private enum TimeoutOutcome<T: Sendable>: Sendable {
    case value(T)
    case fallback
}
