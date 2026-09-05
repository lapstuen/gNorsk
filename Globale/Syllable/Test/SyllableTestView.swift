//
//  SyllableTestView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/21/25.
//


import SwiftUI






struct SyllableTestView: View {
    let sample = "ขออันนี้ครับ"

    var body: some View {
        //let syls = segmentThai(sample)
        let syls = ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(sample))
        
        VStack(alignment: .leading, spacing: 6) {
            Text("Testing: \(sample)").font(.headline)
            ForEach(Array(syls.enumerated()), id: \.offset) { i, s in
                Text("\(i+1). onset=\(s.onset) nucleus=\(s.nucleus) coda=\(s.coda ?? "ø") live=\(s.live)")
                    .monospaced()
            }
        }
        .padding()
    }
}
