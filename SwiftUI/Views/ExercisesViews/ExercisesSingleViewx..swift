//
//  SRSResult.swift
//  gThai
//
//  Created by Geir Lapstuen on 9/2/25.
//


import SwiftUI
import CoreData

enum SRSResult { case good, fail }

@Observable
final class SRSLogic {
    // SM-2 light, hardkodet foreløpig
    func record(_ result: SRSResult, for w: ThaiWords, in ctx: NSManagedObjectContext) {
        let now = Date()
        let minE = 1.30, maxE = 2.80
        func clamp(_ e: Double) -> Double { max(minE, min(maxE, e == 0 ? 2.5 : e)) }

        w.lastReviewedAt = now
        w.dateOne = now

        switch result {
        case .good:
            w.lastResult = 1
            w.repetitions += 1
            w.easiness = clamp(w.easiness + 0.10)
            if w.repetitions == 1 {
                w.dueAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
            } else if w.repetitions == 2 {
                w.dueAt = Calendar.current.date(byAdding: .day, value: 3, to: now)
            } else {
                let prev = max(1.0, (w.dueAt ?? now).timeIntervalSince(now) / 86_400.0)
                let next = Int(ceil(prev * w.easiness))
                w.dueAt = Calendar.current.date(byAdding: .day, value: next, to: now)
            }
        case .fail:
            w.lastResult = 0
            w.lapses += 1
            w.repetitions = 0
            w.easiness = clamp(w.easiness - 0.20)
            let steps = [10, 60, 12*60]
            let idx = min(max(0, Int(w.lapses) - 1), steps.count - 1)
            w.dueAt = Calendar.current.date(byAdding: .minute, value: steps[idx], to: now)
        }

        w.dateTwo = w.dueAt
        try? ctx.save()
    }
}

struct ExercisesSingleView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let word: ThaiWords

    @State private var srs = SRSLogic()
    
    func markResult(id: UUID, success: Bool) {
        appState.sessionResults[id] = success
        appState.refreshToken = UUID()   // tving re-render i Grid
        }

        // Rydd alt når du forlater testen
        func clearSessionResults() {
            appState.sessionResults.removeAll()
            appState.refreshToken = UUID()
        }

    var body: some View {
        VStack(spacing: 24) {
            if word.frequencyRank > 0 {
                Text("#\(String(format: "%04d", word.frequencyRank))")
                    .font(.footnote)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            // ⚠️ Viser IKKE thai-ordet
            Image(systemName: "questionmark.circle")
                .resizable().scaledToFit().frame(width: 140, height: 140)
                .opacity(0.25)

            Spacer(minLength: 12)

            HStack(spacing: 40) {
                Button { handle(success: false) } label: {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.system(size: 48, weight: .bold))
                }.buttonStyle(.plain)

                Button { handle(success: true) } label: {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 48, weight: .bold))
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
    }

    private func handle(success: Bool) {
        srs.record(success ? .good : .fail, for: word, in: ctx)

        let id = word.id ?? { let x = UUID(); word.id = x; try? ctx.save(); return x }()
        markResult(id: id, success: success)     // <- din lokale som skriver til appState
        dismiss()
    }
    
 //   private func handle(success: Bool) {
 //       srs.record(success ? .good : .fail, for: word, in: ctx)
//
 //       // Sørg for at ordet har en UUID
 //       let id = word.id ?? {
 //           let newID = UUID()
 //           word.id = newID
 //           try? ctx.save()
 //           return newID
 //       }()
//
 //       // appState.markResult(id: id, success: success) // ✅ bruker UUID, ikke objectID
 //       dismiss() // rett tilbake til griden
 //   }
}

#Preview {
    // In-memory Core Data preview
    let container = NSPersistentContainer(name: "gNorsk")
    let desc = NSPersistentStoreDescription(); desc.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [desc]
    container.loadPersistentStores(completionHandler: {_,_ in})
    let ctx = container.viewContext
    let w = ThaiWords(context: ctx)
    w.frequencyRank = 30
    try? ctx.save()

    return ExercisesSingleView(word: w)
        .environment(\.managedObjectContext, ctx)
        .environment(AppState())
}
