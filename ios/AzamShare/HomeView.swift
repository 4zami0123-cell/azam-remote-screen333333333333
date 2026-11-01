import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: DeviceStore
    @State private var scanning = false
    @State private var watching: PairInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.plum.ignoresSafeArea()
                if store.devices.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(store.devices) { d in
                                Button { watching = d } label: { row(d) }
                                    .listRowBackground(Theme.panel)
                            }
                            .onDelete { store.devices.remove(atOffsets: $0) }
                        } footer: {
                            Text("اسحب لليسار عشان تحذف جهاز.").foregroundStyle(Theme.muted)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Azam Share")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: { Image(systemName: "qrcode.viewfinder") }
                        .accessibilityLabel("ربط كمبيوتر")
                }
            }
        }
        .sheet(isPresented: $scanning) {
            ScanSheet { info in
                store.add(info)
                scanning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { watching = info }
            }
        }
        .fullScreenCover(item: $watching) { info in
            ViewerView(info: info).environment(\.layoutDirection, .leftToRight)
        }
    }

    private func row(_ d: PairInfo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.headline).foregroundStyle(.white)
                Text(d.hosts.contains { $0.hasPrefix("100.") } ? "من البيت ومن أي مكان" : "من البيت بس")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer").font(.system(size: 56)).foregroundStyle(Theme.amber)
            Text("ما فيه كمبيوتر مربوط").font(.title3.bold())
            Text("شغّل برنامج Azam Share على الكمبيوتر وصوّر الكود اللي يطلع لك.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted).padding(.horizontal, 40)
            Button { scanning = true } label: {
                Label("ربط كمبيوتر", systemImage: "qrcode.viewfinder").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent).foregroundStyle(Theme.plum).controlSize(.large)
        }
    }
}

struct ScanSheet: View {
    var onPaired: (PairInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pasteError = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRScanner { text in
                    guard let info = DeviceStore.parse(text) else { return false }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onPaired(info)
                    return true
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 24).stroke(Theme.amber, lineWidth: 3)
                    .frame(width: 250, height: 250)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("وجّه الكاميرا على الكود اللي في برنامج الكمبيوتر")
                    .padding(12).background(.black.opacity(0.7), in: Capsule()).padding(.bottom, 40)
            }
            .navigationTitle("ربط كمبيوتر").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("لصق") {
                        if let s = UIPasteboard.general.string, let info = DeviceStore.parse(s) { onPaired(info) }
                        else { pasteError = true }
                    }
                }
            }
            .alert("ما لقيت رمز ربط في الحافظة", isPresented: $pasteError) { Button("تمام", role: .cancel) {} }
        }
    }
}
