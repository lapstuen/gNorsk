//
//  SyllableTableView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/21/25.
//


import SwiftUI

struct SyllableTableView: View {
    let text: String
   // private var rows: [ThaiSyllable] { ThaiSeg.segmentThai(text) }
    private var rows: [ThaiSyllable] { ThaiSeg.repairPreposedVowelNucleus(ThaiSeg.segmentThai(text)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(Font.system(size: 7).bold())

            let cellFont: Font   = .system(size: 30, weight: .bold)
            let headFont: Font   = .system(size: 12, weight: .semibold)
            let badgeFont: Font  = .system(size: 22, weight: .medium, design: .monospaced)

            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                // HEADER
                GridRow {
                    Text("Onset")
                    Text("Vokal")
                    Text("Coda")
                    Text("Live")
                }
                .font(headFont)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // RADER
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, s in
                    GridRow {
                        Text(s.onset)
                        Text(s.nucleus)
                        Text(s.coda ?? "ø")
                        HStack(spacing: 8) {
                            Circle()
                                .frame(width: 10, height: 10)
                                .foregroundStyle(s.live ? .green : .red)
                            Text(s.live ? "live" : "dead")
                                .font(badgeFont)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(cellFont)                 // 👈 én gang for hele raden
                    .accessibilityLabel("Syllable \(idx+1)")
                }
            }
            // “Tabell”-header
            
            .padding(.top, 4)
        }
        .padding()
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .monospaced()
    }

    private func cell(_ value: String) -> some View {
        Text(value)
            .font(.title3) // thai ser tydelig ut
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("SyllableTableView") {
    // fri test: bytt strengen når du vil
    SyllableTableView(text: "ขออันนี้ครับ")
        .padding()
}
