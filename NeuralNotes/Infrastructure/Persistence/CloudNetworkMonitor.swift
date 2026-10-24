import Network
import Observation
import Foundation

@MainActor @Observable
final class CloudNetworkMonitor {
    static let shared = CloudNetworkMonitor()
    private(set) var available = false
    private(set) var unmeteredWiFi = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            let wifi = available && path.usesInterfaceType(.wifi) && !path.isExpensive && !path.isConstrained
            Task { @MainActor [weak self] in self?.available = available; self?.unmeteredWiFi = wifi }
        }
        monitor.start(queue: DispatchQueue(label: "NeuralNotes.CloudNetwork"))
    }
    deinit { monitor.cancel() }
}
