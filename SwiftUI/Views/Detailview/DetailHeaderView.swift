//
//  DetailHeaderView.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/18/25.
//


// DetailHeaderView.swift
import SwiftUI

struct DetailHeaderView: View {
    @Binding var showPhotoVC: Bool
    @Binding var kildeIkon: UIImage?
    let thaiWord: String
    let dismiss: () -> Void
    let openURL: OpenURLAction

    var body: some View {
        HStack {
            Button("Back") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            if let ikon = kildeIkon {
                Image(uiImage: ikon)
                    .resizable()
                    .frame(width: 33, height: 33)
                    .padding(.leading, 4)
            }

            Spacer()

            Button("Choose Photo") { showPhotoVC = true }
                .padding(.trailing, 10)

            Menu {
                
                
                Button("Thai-language site", action: {
                    let thiaw = thaiWord
                    UIPasteboard.general.string = thiaw
                    if let url = URL(string: "http://www.thai-language.com/") {
                        openURL(url)
                    }
                })
                
                Button {
                    let q = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "http://www.google.com/search?q=site:thai-language.com%20\(q)") {
                        openURL(url)
                    }
                } label: {
                    Label("Thai-language search", systemImage: "magnifyingglass.circle")
                }
                
                
                
                
                Button("Thai-language search", action: {
                    let encoded = thaiWord.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let url = URL(string: "http://www.google.com/search?q=site:thai-language.com%20\(encoded)")!
                    openURL(url)
                })
                
                Button("GoogleTranslate site", action: {
                    UIPasteboard.general.string = thaiWord
                    openGoogleTranslate(thaiWord, using: openURL)
                })
                
                
                
                
                // menyen kan flyttes hit senere ved behov
                Text("ThaiWord: \(thaiWord)")
                
                Button {
                  // commando her
                } label: {
                    Label("test", systemImage: "star")
                }
                Button {
                  // commando her
                } label: {
                    Label("test", systemImage: "star")
                }
                Button {
                  // commando her
                } label: {
                    Label("test", systemImage: "star")
                }
                Button {
                  // commando her
                } label: {
                    Label("test", systemImage: "star")
                }
               
                
               Divider()
                
                Button("Show phonetic") {
                    UIPasteboard().string = thaiWord
                    openThaiLanguage(word: thaiWord, mode: .home, openURL: openURL)
                }
                
               
                
      
                
            } label: {
                Image(systemName: "line.horizontal.3")
                    .imageScale(.large)
                    .padding(.horizontal)
            }
            
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    
}
