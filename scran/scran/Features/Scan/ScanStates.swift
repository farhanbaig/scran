//
//  ScanStates.swift
//  scran
//
//  Shared progress + error states. Every scan visibly succeeds or visibly fails
//  with a retry path (LAW 3 — no silent failures).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ScanProgressView: View {
    var accent: Color
    var message: String
    #if canImport(UIKit)
    var image: UIImage?
    #endif

    var body: some View {
        VStack(spacing: 24) {
            #if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ScranColor.line))
                    .opacity(0.7)
            }
            #endif
            ProgressView().tint(accent).scaleEffect(1.4)
            Text(message)
                .font(ScranFont.mono(14, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanErrorView: View {
    var accent: Color
    var title: String
    var message: String
    var retake: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38)).foregroundStyle(accent)
            Text(title)
                .font(ScranFont.display(26, relativeTo: .title)).textCase(.uppercase)
                .foregroundStyle(ScranColor.textPrimary).multilineTextAlignment(.center)
            Text(message)
                .font(ScranFont.body(15, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted).multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Retake", systemImage: "camera") { retake() }
            Button("Cancel") { cancel() }
                .font(ScranFont.body(15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(ScranColor.textMuted)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
