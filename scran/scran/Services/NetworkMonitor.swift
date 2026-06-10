//
//  NetworkMonitor.swift
//  scran
//
//  Online/offline state for LAW 3 messaging: scanning is disabled with clear
//  copy when offline; manual + saved-meal logging keeps working.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.wiresidestudios.scran.network")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
