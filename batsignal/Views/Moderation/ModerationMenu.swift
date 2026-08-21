import SwiftUI

struct BlockTarget: Equatable {
    let userId: String
    let displayName: String
}

extension View {
    // Attaches report and block actions to anything a user authored. A long
    // press rather than a visible control, so the affordance stays out of the
    // way of content that's almost always fine — but it's on every comment,
    // every signal, and every person, which is what the guideline asks for.
    //
    // Callers pass nil for either action where it doesn't apply: there's
    // nothing to report about your own comment, and nobody to block on it.
    func moderationMenu(report: ReportTarget?, block: BlockTarget? = nil) -> some View {
        modifier(ModerationMenuModifier(report: report, block: block))
    }
}

private struct ModerationMenuModifier: ViewModifier {
    let report: ReportTarget?
    let block: BlockTarget?

    @State private var activeReport: ReportTarget?
    @State private var showBlockConfirmation = false
    @State private var isBlocking = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let report {
                    Button {
                        activeReport = report
                    } label: {
                        Label(Strings.Moderation.report, systemImage: "flag")
                    }
                }
                if block != nil {
                    Button(role: .destructive) {
                        showBlockConfirmation = true
                    } label: {
                        Label(Strings.Moderation.block, systemImage: "hand.raised")
                    }
                }
            }
            .sheet(item: $activeReport) { target in
                ReportSheet(target: target)
            }
            .alert(
                block.map { Strings.Moderation.blockTitle($0.displayName) } ?? "",
                isPresented: $showBlockConfirmation
            ) {
                Button(Strings.Common.cancel, role: .cancel) {}
                Button(Strings.Moderation.blockConfirm, role: .destructive, action: performBlock)
            } message: {
                Text(Strings.Moderation.blockMessage)
            }
            .alert(
                Strings.Moderation.blockFailed,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(Strings.Common.ok, role: .cancel) { errorMessage = nil }
            }
            .disabled(isBlocking)
    }

    private func performBlock() {
        guard let block else { return }
        isBlocking = true
        Task {
            do {
                try await ModerationService.shared.block(userId: block.userId)
            } catch {
                errorMessage = Strings.Moderation.blockFailed
            }
            isBlocking = false
        }
    }
}
