//
//  NoticeKind.swift
//  gThai
//
//  Created by Geir Lapstuen on 8/10/25.
//
import SwiftUI

enum NoticeKind { case info, success, warning, error }

@Observable
final class Notifier {
    static let shared = Notifier()
    var message: String? = nil
    var kind: NoticeKind = .info

    func show(_ kind: NoticeKind, _ text: String, duration: TimeInterval = 2.5) {
        self.kind = kind
        self.message = text
        guard duration > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            // Ikke auto-skjul for error; kun for andre typer
            if kind != .error { self?.message = nil }
        }
    }

    func hide() { message = nil }
}
