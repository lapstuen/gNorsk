import SwiftUI

private struct ThaiMockWord: Identifiable {
    let id = UUID()
    let thaiWord: String
    let sentence: String
    let groupId: Int16
}

private struct ThaiGridViewMock: View {
    @State private var moveToPinnedGroup = false

    let words: [ThaiMockWord] = [
        ThaiMockWord(thaiWord: "ออกกำลังกาย", sentence: "1 ɔ̀ɔkˀ kamlang kai [Jeg trener hver morgen.]", groupId: 101),
        ThaiMockWord(thaiWord: "สวัสดี", sentence: "2 sà-wàt-dii [Hei!]", groupId: 102),
        ThaiMockWord(thaiWord: "ขอบคุณ", sentence: "3 khɔ̀ɔp-khun [Takk!]", groupId: 103)
    ]

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(words) { word in
                   // ThaiGridItemMock(word: word, moveToPinnedGroup: $moveToPinnedGroup)
                }
            }
            .padding()
        }
    }
}
