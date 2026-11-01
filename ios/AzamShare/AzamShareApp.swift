import SwiftUI

@main
struct AzamShareApp: App {
    @StateObject private var store = DeviceStore()
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
        }
    }
}

enum Theme {
    static let plum = Color(red: 0.102, green: 0.078, blue: 0.149)
    static let panel = Color(red: 0.149, green: 0.114, blue: 0.212)
    static let muted = Color(red: 0.663, green: 0.608, blue: 0.820)
    static let amber = Color(red: 0.949, green: 0.710, blue: 0.267)
    static let red = Color(red: 0.910, green: 0.416, blue: 0.478)
}
