#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

enum WorldDashboardLayoutMetrics {
    static let outerPadding: CGFloat = 18
    static let columnSpacing: CGFloat = 12
    static let panelSpacing: CGFloat = 10
    static let sidebarPanelWidth: CGFloat = 180
    static let primaryColumnWidth: CGFloat = 612
    static let wideLayoutMinimumWidth: CGFloat = 1120
    static let wideLayoutMinimumHeight: CGFloat = 720
    static let maximumScale: CGFloat = 1.0
}

struct DashboardMeasuredSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next.width > 0, next.height > 0 else {
            return
        }
        value = next
    }
}

struct FittedDashboardView<Content: View>: View {
    let availableSize: CGSize
    let maxScale: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var measuredSize: CGSize = .zero

    private var contentSize: CGSize {
        guard measuredSize.width > 0, measuredSize.height > 0 else {
            return availableSize
        }
        return measuredSize
    }

    private var scale: CGFloat {
        let widthScale = availableSize.width / max(contentSize.width, 1)
        let heightScale = availableSize.height / max(contentSize.height, 1)
        return max(0.1, min(maxScale, min(widthScale, heightScale)))
    }

    var body: some View {
        let scaledWidth = contentSize.width * scale
        let scaledHeight = contentSize.height * scale

        content()
            .fixedSize(horizontal: true, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: DashboardMeasuredSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(DashboardMeasuredSizeKey.self) { newSize in
                guard newSize.width > 0, newSize.height > 0 else {
                    return
                }
                if abs(newSize.width - measuredSize.width) > 0.5 || abs(newSize.height - measuredSize.height) > 0.5 {
                    measuredSize = newSize
                }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: scaledWidth, height: scaledHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

@MainActor
struct GameRootView: View {
    @ObservedObject var session: GameSessionController
    @State var showingEditorConfirm = false
    @State var showDebugLightingOverlay = false
    @State var screenshotNotice: String?
    @State var screenshotNoticeWorkItem: DispatchWorkItem?

    let palette = UltimaPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            PixelStars(color: starfieldColor).ignoresSafeArea()
            PixelKeyCapture(
                onCommand: {
                    guard !showingEditorConfirm else { return }
                    session.send($0)
                },
                onThemeToggle: {
                    guard !showingEditorConfirm else { return }
                    session.cycleVisualTheme()
                },
                onEditorRequest: {
                    guard !showingEditorConfirm else { return }
                    requestEditor()
                },
                onScreenshotRequest: {
                    captureScreenshot()
                },
                onDebugOverlayToggle: {
                    toggleDebugOverlay()
                }
            )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            switch session.state.mode {
            case .title:
                titleView
            case .characterCreation:
                creatorView
            case .ending:
                endingView
            default:
                worldView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            ZStack {
                if session.state.mode == .pause && !showingEditorConfirm {
                    pauseOverlay
                }
                if showingEditorConfirm {
                    editorConfirmOverlay
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let screenshotNotice {
                Text(screenshotNotice)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.background)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(palette.lightGold)
                    .overlay(Rectangle().stroke(palette.titleGold, lineWidth: 2))
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .onMoveCommand(perform: handleMove)
    }
}
#endif
