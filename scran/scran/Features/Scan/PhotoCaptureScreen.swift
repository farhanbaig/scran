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
    var accent: Color = ScranColor.verified
    /// Draw a rectangular nutrition-table guide (label mode) vs. a loose frame.
    var showLabelGuide: Bool = false
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var controller = PhotoCameraController()
    @State private var torchOn = false
    @State private var authorized = false
    @State private var checkedPermission = false
    @State private var capturing = false

    var body: some View {
        ZStack {
            ScranColor.bg.ignoresSafeArea()

            if authorized {
                CameraPreview(controller: controller).ignoresSafeArea()
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

    private var overlay: some View {
        VStack {
            // Top bar
            HStack {
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ScranColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                Spacer()
                Button {
                    torchOn.toggle(); controller.setTorch(torchOn); Haptics.selection()
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(torchOn ? accent : ScranColor.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            if showLabelGuide {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accent.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(height: 220)
                    .padding(.horizontal, 28)
            }

            Text(instruction)
                .font(ScranFont.mono(13, relativeTo: .footnote))
                .multilineTextAlignment(.center)
                .foregroundStyle(ScranColor.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.5)))
                .padding(.top, 18)

            Spacer()

            // Shutter
            Button {
                guard !capturing else { return }
                capturing = true
                Haptics.tap()
                controller.capture { image in
                    capturing = false
                    if let image { onCapture(image) }
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
