import UIKit

/// Connects straight to the PC over a WebSocket and shows the JPEG frames it sends.
/// Tries each address in order (home network first, then Tailscale) and reconnects on its own.
@MainActor
final class Streamer: ObservableObject {
    enum State: Equatable { case connecting, live, failed, badCode }

    @Published var image: UIImage?
    @Published var state: State = .connecting

    let info: PairInfo
    private var running = false
    private var task: URLSessionWebSocketTask?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(info: PairInfo) { self.info = info }

    func start() {
        guard !running else { return }
        running = true
        Task { await loop() }
    }

    func stop() {
        running = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func loop() async {
        while running {
            if state != .live { state = .connecting }
            var connected = false
            for host in info.hosts where running {
                if await watch(host: host) { connected = true; break }
                if state == .badCode { running = false; return }
            }
            guard running else { return }
            if !connected { state = .failed }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// Returns true if this address delivered at least one frame.
    private func watch(host: String) async -> Bool {
        let h = host.contains(":") ? "[\(host)]" : host
        guard let url = URL(string: "ws://\(h):\(info.port)/?token=\(info.token)") else { return false }
        let t = session.webSocketTask(with: url)
        t.maximumMessageSize = 16 * 1024 * 1024
        task = t
        t.resume()
        var gotFrame = false
        while running {
            do {
                let message = try await t.receive()
                if case .data(let data) = message, let img = UIImage(data: data) {
                    image = img
                    if !gotFrame { gotFrame = true; state = .live }
                }
            } catch {
                if t.closeCode.rawValue == 4001 { state = .badCode }
                break
            }
        }
        t.cancel(with: .goingAway, reason: nil)
        if gotFrame && running { state = .connecting }
        return gotFrame
    }
}
