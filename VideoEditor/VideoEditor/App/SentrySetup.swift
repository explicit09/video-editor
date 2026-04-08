import Foundation
import Sentry

enum SentrySetup {
    static func configure() {
        guard let dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"],
              !dsn.isEmpty else {
            print("[Sentry] No DSN configured, skipping initialization")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true

            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            options.sendDefaultPii = false
        }
    }
}

extension SentrySetup {
    @discardableResult
    static func span<T>(_ operation: String, description: String, body: () async throws -> T) async rethrows -> T {
        let parentSpan = SentrySDK.span
        let span: Span
        if let parentSpan {
            span = parentSpan.startChild(operation: operation, description: description)
        } else {
            span = SentrySDK.startTransaction(name: description, operation: operation)
        }

        do {
            let result = try await body()
            span.finish(status: .ok)
            return result
        } catch {
            span.finish(status: .internalError)
            throw error
        }
    }
}
