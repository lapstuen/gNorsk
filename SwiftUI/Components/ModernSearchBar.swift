import SwiftUI

struct ModernSearchBar: View {
   @Binding var searchText: String
   var doTranslation: () -> Void

   @ObservedObject private var dictationHelper = DictationHelper()
   @FocusState private var isFocused: Bool

   var body: some View {
      HStack(spacing: 8) {
         Image(systemName: "magnifyingglass")
            .foregroundColor(.gray)

         TextField("Search", text: $searchText)
              .textInputAutocapitalization(.never)
              .disableAutocorrection(true)
             
            .focused($isFocused)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .onSubmit {
               doTranslation()
            }

         if !searchText.isEmpty {
            Button {
               searchText = ""
               isFocused = false
            } label: {
               Image(systemName: "xmark")
                  .foregroundColor(.green)
            }
         } else {
            Button {
               dictationHelper.startDictation()
            } label: {
               Image(systemName: "mic.fill")
                  .foregroundColor(.gray)
            }
         }
      }
      .padding(10)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .padding(.horizontal)
      .onReceive(dictationHelper.$recognizedText) { text in
         self.searchText = text
      }
   }
}
