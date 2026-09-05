//
//  FlowLayout.swift
//  gThai
//
//  Created by Geir Lapstuen on 7/15/25.
//

import SwiftUI

struct FlowLayout<Content: View>: View {
   let spacing: CGFloat
   let alignment: HorizontalAlignment
   let content: () -> Content

   init(spacing: CGFloat = 8,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content) {
      self.spacing = spacing
      self.alignment = alignment
      self.content = content
   }

   var body: some View {
      GeometryReader { geometry in
         self.generateContent(in: geometry)
      }
   }

   private func generateContent(in geometry: GeometryProxy) -> some View {
      var width = CGFloat.zero
      var height = CGFloat.zero

      return ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
         content()
            .fixedSize()
            .alignmentGuide(.leading, computeValue: { d in
               if (abs(width - d.width) > geometry.size.width) {
                  width = 0
                  height -= d.height + spacing
               }
               let result = width
               if d.width != 0 {
                  width -= d.width + spacing
               }
               return result
            })
            .alignmentGuide(.top, computeValue: { _ in
               let result = height
               if height != 0 {
                  height = result
               }
               return result
            })
      }
   }
}
