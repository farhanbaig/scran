//
//  CrashReporter.swift
//  scran
//
//  Crash + error reporting behind a protocol. Default impl logs in DEBUG.
//  Wire Sentry by adding the SPM package and implementing the template.
//

import Foundation

protocol CrashReporting: Sendable {
    func bootstrap()
    func capture(_ error: Error, context: [String: String])
    func breadcrumb(_ message: String)
}

struct ConsoleCrashReporter: CrashReporting {
    func bootstrap() {}
    func capture(_ error: Error, context: [String: String]) {
        #if DEBUG
        print("🛑 \(error.localizedDescription) \(context)")
        #endif
    }
    func breadcrumb(_ message: String) {
        #if DEBUG
        print("· \(message)")
        #endif
    }
}

// MARK: - Sentry adapter (template — uncomment after adding the SPM package)
/*
import Sentry

struct SentryCrashReporter: CrashReporting {
    func bootstrap() {
        SentrySDK.start { options in
            options.dsn = ScranConfig.sentryDSN
            options.tracesSampleRate = 0.2
            options.enableAutoSessionTracking = true   // powers crash_free_session
        }
    }
    func capture(_ error: Error, context: [String: String]) {
        SentrySDK.capture(error: error) { scope in
            for (k, v) in context { scope.setTag(value: v, key: k) }
        }
    }
    func breadcrumb(_ message: String) {
        let crumb = Breadcrumb(level: .info, category: "app")
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}
*/
