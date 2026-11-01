import SwiftUI

struct ViewerView: View {
    @StateObject private var s: Streamer
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var showUI = true

    init(info: PairInfo) { _s = StateObject(wrappedValue: Streamer(info: info)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = s.image {
                Image(uiImage: img)
                    .resizable().interpolation(.medium).scaledToFit()
                    .scaleEffect(scale).offset(offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(zoom.simultaneously(with: pan))
                    .onTapGesture(count: 2) { withAnimation(.spring()) { resetZoom() } }
                    .onTapGesture { withAnimation { showUI.toggle() } }
                    .ignoresSafeArea()
            }
            if s.state != .live { statusOverlay }
            if showUI { topBar }
        }
        .statusBarHidden(!showUI)
        .persistentSystemOverlays(showUI ? .automatic : .hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; s.start() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; s.stop() }
    }

    private var zoom: some Gesture {
        MagnificationGesture()
            .onChanged { scale = min(max(baseScale * $0, 1), 6) }
            .onEnded { _ in baseScale = scale; if scale <= 1.01 { resetZoom() } }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { v in
                guard scale > 1 else { return }
                offset = CGSize(width: baseOffset.width + v.translation.width,
                                height: baseOffset.height + v.translation.height)
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func resetZoom() { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }

    private var topBar: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.black.opacity(0.6), in: Circle())
                }
                .accessibilityLabel("إغلاق")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(s.state == .live ? Theme.amber : Theme.muted).frame(width: 8, height: 8)
                    Text(s.state == .live ? "مباشر: \(s.info.name)" : s.info.name).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(.black.opacity(0.6), in: Capsule())
            }
            .padding()
            Spacer()
        }
    }

    private var statusOverlay: some View {
        VStack(spacing: 12) {
            switch s.state {
            case .badCode:
                Image(systemName: "key.slash").font(.largeTitle).foregroundStyle(Theme.red)
                Text("رمز الربط تغيّر").font(.headline)
                Text("صوّر الكود من جديد من برنامج الكمبيوتر.").foregroundStyle(Theme.muted)
            case .failed:
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Theme.red)
                Text("ما قدرت أوصل للكمبيوتر").font(.headline)
                Text("تأكد إن برنامج Azam Share شغّال، وإذا أنت برا البيت تأكد إن Tailscale شغّال في الجوال والكمبيوتر. بحاول مرة ثانية تلقائياً.")
                    .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
            default:
                ProgressView().tint(.white).controlSize(.large)
                Text("جارِ الاتصال بـ \(s.info.name)…").foregroundStyle(Theme.muted)
            }
        }
        .padding(24).frame(maxWidth: 340)
        .background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .environment(\.layoutDirection, .rightToLeft)
    }
}
