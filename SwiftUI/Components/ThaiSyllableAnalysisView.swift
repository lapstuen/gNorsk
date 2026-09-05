//
//  ThaiSyllableAnalysisView.swift
//  gThai
//
//  Created by Claude Code on 9/28/25.
//

import SwiftUI
import CoreData

struct ThaiSyllableAnalysisView: View {
    let thaiWord: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Header info - samme stil som HybridSegmentationView
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Norwegian word:").font(.caption).foregroundColor(.secondary)

                            HStack(alignment: .center, spacing: 12) {
                                Button(action: {
                                    CloudTTSTest.speakNorsk(thaiWord)
                                }) {
                                    Image(systemName: "speaker.wave.2")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 18))
                                }
                                .buttonStyle(.plain)

                                Text(thaiWord)
                                    .font(.title3)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Divider()

                        // Stavelse-analyse - samme stil som "Segmenterte deler xx"
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Syllable Analysis").font(.headline)

                            ThaiSyllableTableView(text: thaiWord)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(minHeight: 1200)
                }
                .coordinateSpace(name: "scroll")
                .scrollIndicators(.visible)
                #if targetEnvironment(macCatalyst)
                .scrollContentBackground(.visible)
                .scrollBounceBehavior(.automatic)
                #endif
                .background(Color(.systemBackground))

                // Mac-spesifik overlay for scroll-events
                #if targetEnvironment(macCatalyst)
                Rectangle()
                    .fill(Color.black.opacity(0.001)) // Nesten usynlig men ikke helt gjennomsiktig
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.all)
                #endif
            }
            .navigationTitle("Syllable Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 700)
    }
}

#Preview {
    ThaiSyllableAnalysisView(thaiWord: "จะ")
}
