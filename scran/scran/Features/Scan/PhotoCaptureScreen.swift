//
//  PhotoCaptureScreen.swift
//  scran
//
//  Reusable full-screen camera capture with a guide overlay and torch. Used by
//  the label and plate flows. No silent failure: permission denial and capture
//  failure both show clear messaging (LAW 3).
//

import SwiftUI
#if canImport(UIKit)
import UIKit

struct PhotoCaptureScreen: View {
    let title: String
    let instruction: String
    var accent: Color = .white
    /// Framing guide + crop region. `.label` (table) / `.plate` (square) crop the
    /// capture to the box; `.none` keeps the full frame.
    var guide: CaptureGuide = .none
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var controller = PhotoCameraController()
    @State private var torchOn = false
    @State private var authorized = false
    @State private var checkedPermission = false
    @State private var capturing = false
    /// Live size of the camera view, so the drawn guide and the crop use the
    /// exact same rectangle.
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {
            ScranColor.bg.ignoresSafeArea()

            if authorized {
                CameraPreview(controller: controller).ignoresSafeArea()
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewSize = geo.size }
                        .onChange(of: geo.size) { _, s in viewSize = s }
                }
                guideOverlay
                overlay
            } else if checkedPermission {
                permissionDenied
            }
        }
        .task {
            authorized = await CameraPermission.request()
            checkedPermission = true
            if authorized { controller.configure() }
        }
        .onDisappear { controller.stop() }
        .statusBarHidden()
    }

    /// Dimmed scrim with the framing box punched out, so it's obvious that only
    /// what's inside the box is captured.
    @ViewBuilder private var guideOverlay: some View {
        if guide.cropsToGuide, viewSize != .zero {
            let r = guide.rect(in: viewSize)
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: guide.cornerRadius, style: .continuous)
                                    .frame(width: r.width, height: r.height)
                                    .position(x: r.midX, y: r.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: guide.cornerRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 2.5)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var overlay: some View {
        VStack {
            // Top bar
            HStack {
                Button { Haptics.tap(); onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .accessibilityLabel("Close camera")
                Spacer()
                Button {
                    torchOn.toggle(); controller.setTorch(torchOn); Haptics.selection()
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(torchOn ? accent : .white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            Text(instruction)
                .font(ScranFont.body(14, weight: .semibold, relativeTo: .footnote))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Shutter
            Button {
                guard !capturing else { return }
                capturing = true
                Haptics.tap()
                let g = guide
                let vs = viewSize
                controller.capture { image in
                    capturing = false
                    guard var image else { return }
                    if g.cropsToGuide, vs != .zero {
                        image = image.croppedToPreviewRect(g.rect(in: vs), viewSize: vs)
                    }
                    onCapture(image)
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(capturing ? accent : .white).frame(width: 60, height: 60)
                }
            }
            .padding(.bottom, 36)
            .accessibilityLabel("Capture photo")
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40)).foregroundStyle(ScranColor.textMuted)
                .accessibilityHidden(true)
            Text("Camera access needed")
                .font(ScranFont.display(24, relativeTo: .title)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary)
            Text("Enable camera access in Settings to scan barcodes and labels.")
                .font(ScranFont.body(15, relativeTo: .body))
                .multilineTextAlignment(.center).foregroundStyle(ScranColor.textMuted)
            SecondaryButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel") { onCancel() }
                .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
        }
        .padding(32)
    }
}
#endif
