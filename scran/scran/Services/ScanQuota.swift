//
//  ScanQuota.swift
//  scran
//
//  Surfaces the server-side AI scan quota as a calm counter ("2 AI scans left
//  today"). Truth lives in Postgres (ai_scan_events) and is enforced inside the
//  Edge Functions; this is the read side for UI.
//

import Foundation
import Observation

@MainActor
@Observable
final class ScanQuota {
    /// Scans used today (UTC). nil while unknown.
    private(set) var usedToday: Int?
    var isPro: Bool = false

    var remaining: Int? {
        guard !isPro, let used = usedToday else { return nil }
        return max(0, ScranConfig.freeDailyScans - used)
    }

    var isExhausted: Bool {
        guard !isPro else { return false }
        if let r = remaining { return r <= 0 }
        return false
    }

    /// Calm counter copy for the Today/Log screens.
    var counterText: String? {
        guard !isPro, let r = remaining else { return nil }
        if r <= 0 { return "No AI scans left today" }
        return r == 1 ? "1 AI scan left today" : "\(r) AI scans left today"
    }

    /// Refresh from the SECURITY DEFINER RPC (counts only the caller's rows).
    func refresh() async {
        guard !isPro else { usedToday = 0; return }
        do {
            let used = try await SupabaseClient.shared.rpc(
                "ai_scans_used_today", returning: Int.self)
            usedToday = used
        } catch {
            // Leave previous value; never block the user on a counter read.
        }
    }

    /// Optimistically decrement after a successful scan; server is source of truth.
    func noteScanUsed(remainingFromServer: Int?) {
        if let r = remainingFromServer {
            usedToday = max(0, ScranConfig.freeDailyScans - r)
        } else if let u = usedToday {
            usedToday = u + 1
        }
    }
}
