//
//  ExercisesView.swift
//  gThai
//
//  Created by Geir Lapstuen on 2025-07-03.
//
import SwiftUI
import AVFoundation
//let g = GlFunctions()


struct ExercisView: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    // @Bindable private var boundAppState: AppState
    @Environment(\.openURL) private var openURL
    @State private var StartIndex = 0
    @State private var AntallOrdPrGang = 20
    @State private var AntallGangerBeforeOk = 3
    //  state private var words = [ThaiWord]()
    let words: [ThaiWords]
    // @State private var word: ThaiWord
    @State private var currentIndex = 0
    @State private var visThai = true
    @State private var groupName = ""
    @State private var showOverlay = false
    // @Binding var showingSheet: Bool = false
    @State private var speechManager = SpeechManager()
    // ...
    //init(words: [ThaiWord] = []) {
    //   _words = State(initialValue: words)
    //}
    private func loadWords() {
        groupName = appState.valgtGruppeNavn
        // let request = g.selectWordRequest(thaiWord: String(appState.valgtGruppeId), number: AntallOrdPrGang)
        // words = g.getAllWords(request: request, limit: AntallOrdPrGang)
        // currentIndex = 0
        visThai = false
    }
    /// Call this method when the user explicitly selects a group to reload words accordingly.
    public func reloadForSelectedGroup() {
        loadWords()
    }
    var body: some View {
        ZStack {
            Color.clear
            if !words.isEmpty {
                VStack {
                    
                    HStack {
                        Image(systemName: "x.circle.fill")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .foregroundColor(.white)
                            .padding(8)
                            .onTapGesture {
                                // appState.activeSheet = nil
                                isPresented = false
                            }
                        Spacer()
                        Text(appState.valgtGruppeNavn)
                        Spacer()
                        Menu {
                            Button("Antall ord", action: { showOverlay = true })
                            Button("Thai-language", action: {
                                let thiaw = words[currentIndex].thaiWord
                                UIPasteboard.general.string = thiaw
                                if let url = URL(string: "http://www.thai-language.com/") {
                                    openURL(url)
                                }
                            })
                            Button("GoogleTranslate", action: {
                                let thiaw = words[currentIndex].thaiWord ?? ""
                                UIPasteboard.general.string = thiaw
                                openGoogleTranslate(thiaw, using: openURL)
                            })
                        } label: {
                            Image(systemName: "line.3.horizontal.circle.fill")
                                .resizable()
                                .frame(width: 44, height: 44)
                                .foregroundColor(.white)
                        }.padding(8)
                            .popover(isPresented: $showOverlay) {
                                VStack {
                                    HStack {
                                        Button {
                                            showOverlay = false
                                        } label: {
                                            Image(systemName: "x.circle.fill")
                                                .resizable()
                                                .frame(width: 30, height: 30)
                                                .contentShape(Rectangle())
                                                .frame(width: 44, height: 44)
                                        }.padding()
                                        Spacer()
                                    }
                                    .padding()
                                    Spacer()
                                    Text("no of words: \(words.count.formatted())")
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.blue, .purple]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        ).padding()
                                        .cornerRadius(25)
                                    Spacer()
                                }
                                .frame(width: 350, height: 250)
                                .background(Color(.systemGray6))
                            }
                    }
                    .frame(height: 70)
                    .background(Color.red)
                    if visThai {
                        Text(words[currentIndex].sentence ?? "xxx")
                            .font(.caption)
                            .glassEffect()
                        Text(words[currentIndex].thaiWord ?? "xxx")
                            .font(.largeTitle)
                            .bold()
                            .glassEffect()
                        //     Text("Example: \n Not have!")
                        //        .padding(.top, 10)
                        //        .multilineTextAlignment(.center)
                    }
                    Spacer()
                    Text(words[currentIndex].englishWord ?? "xxx")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .glassEffect(.regular.tint(.orange).interactive())
                    HStack {
                        Spacer()
                        Image(uiImage: words[currentIndex].uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                            .shadow(radius: 7)
                            .glassEffect()
                            .onTapGesture {
                                g.talkTh(talkText: words[currentIndex].thaiWord ?? "xxx",rate: 0.2, language: "no")
                                visThai = true
                            }
                        Spacer()
                    }
                    HStack {
                        Button(action: {
                            currentIndex = (currentIndex + 1) % words.count
                            visThai = false
                        }) {
                            Image(systemName: "hand.thumbsdown.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                        }
                        .disabled(!visThai)
                        .opacity(visThai ? 1 : 0)
                        .animation(.easeInOut, value: visThai)
                        .glassEffect()
                        Spacer()
                        Button(action: {
                            currentIndex = (currentIndex + 1) % words.count
                            visThai = false
                        }) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                        }
                        .disabled(!visThai)
                        .opacity(visThai ? 1 : 0)
                        .animation(.easeInOut, value: visThai)
                        .glassEffect()
                    }
                    .padding(.horizontal)
                }
                Spacer()
                //HStack {
                //   Text(word.dateOne.description)
                //      .font(.footnote)
                //       .bold()
                //    Text(word.dateTwo.description)
                //      .font(.footnote)
                //      .bold()
                // }
            } else {
                Text("Ingen ord å vise.")
            }
        }.onAppear{
            appState.currentWordID = words.isEmpty ? nil : words[currentIndex].objectID
        }
    }
}





private struct ThaiWordMock: Identifiable {
    let id = UUID()
    let thaiWord: String
    let sentence: String
    let englishWord: String
    let image: UIImage
}





