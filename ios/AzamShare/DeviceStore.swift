import Foundation

struct PairInfo: Codable, Identifiable, Hashable {
    let name: String
    let hosts: [String]
    let port: Int
    let token: String
    var id: String { name + token }
}

final class DeviceStore: ObservableObject {
    @Published var devices: [PairInfo] = [] {
        didSet { save() }
    }
    private let key = "devices"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([PairInfo].self, from: data) {
            devices = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Adds or replaces a PC (same computer name = re-paired with a new code or new addresses).
    func add(_ info: PairInfo) {
        devices.removeAll { $0.name == info.name }
        devices.insert(info, at: 0)
    }

    static func parse(_ text: String) -> PairInfo? {
        let prefix = "AZAMSHARE:"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let info = try? JSONDecoder().decode(PairInfo.self, from: Data(json.utf8)),
              !info.hosts.isEmpty else { return nil }
        return info
    }
}
