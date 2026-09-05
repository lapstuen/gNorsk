//
//  FollowWindowOverlay.swift
//  gThai
//
//  Created by Geir Lapstuen on 13/9/2568 BE.
//


import SwiftUI

struct FollowWindowOverlay<Overlay: View>: ViewModifier {
    @Binding var isPresented: Bool
    let overlay: (_ close: @escaping () -> Void, _ size: CGSize) -> Overlay

    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack {
                content

                if isPresented {
                    // Dim bakgrunnen og fang klikk
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }

                    overlay({ isPresented = false }, geo.size)
                        .transition(.opacity.combined(with: .scale))
                        .animation(.snappy, value: isPresented)
                }
            }
        }
    }
}

extension View {
    func followWindowOverlay<Overlay: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder overlay: @escaping (_ close: @escaping () -> Void, _ size: CGSize) -> Overlay
    ) -> some View {
        modifier(FollowWindowOverlay(isPresented: isPresented, overlay: overlay))
    }
}