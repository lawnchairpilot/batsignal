import SwiftUI
import UIKit

struct CreateEventView: View {
    @StateObject private var viewModel = CreateEventViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false
    // Lights the preview circle while the signal is on its way out. Held here
    // rather than in EventSymbolHeader because it's the send button that knows
    // when the signal goes.
    @State private var flare: Double = 0

    // How long the lit icon stays up before the sheet closes, whether or not
    // the write has come back by then. Long enough to register as the icon
    // you built lighting up, short enough not to feel like a wait.
    private let flareDwell: Duration = .milliseconds(550)

    // Whether there is a signal here at all. Drives how the send button *looks*,
    // which is not the same question as whether it can be tapped: the send is
    // the moment the button matters most, and canSubmit has already gone false
    // by then, so keying the fill off that would grey the button out at exactly
    // the wrong time.
    private var isArmed: Bool {
        !viewModel.activity.isEmpty
    }

    private var canSubmit: Bool {
        isArmed && !viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            cardContent
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .task {
            await viewModel.loadGroups()
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .bottom) {
            Form {
                Section {
                    EventSymbolHeader(
                        selectedImage: $viewModel.selectedImage,
                        emoji: $viewModel.emoji,
                        imageURL: .constant(nil),
                        flare: flare
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    VStack(alignment: .center, spacing: 14) {
                        CenteredTextField(text: $viewModel.activity, placeholder: Strings.Event.activityPlaceholder)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .onChange(of: viewModel.activity) { _, newValue in
                                if newValue.count > Event.activityCharacterLimit {
                                    viewModel.activity = String(newValue.prefix(Event.activityCharacterLimit))
                                }
                            }
                        Rectangle()
                            .fill(Blipper.hairline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    whoPicker

                    EventDurationWheel(
                        durationMinutes: $viewModel.selectedDurationMinutes,
                        vagueLabel: $viewModel.selectedVagueLabel
                    )
                    .listRowBackground(Color.clear)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundColor(Blipper.roseBright).font(.blipperUI(.caption1))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollDisabled(true)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 200)
            }

            sendButton
        }
        .blipperBackground()
        .overlay(alignment: .topLeading) {
            cancelButton
                .padding(.leading, 24)
                .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cancelButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Blipper.roseBright)
                .frame(width: 44, height: 44)
                .background(Blipper.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Blipper.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // Was a swipe up across a stack of glowing lines, which sat low enough that
    // reaching for it from underneath caught the home indicator and threw the
    // app out instead. A button in the same spot can't be confused for the
    // system's gesture — but it keeps the breathing the lines had, because
    // that pulse is what made this read as a signal waiting to be sent rather
    // than a form waiting to be submitted.
    private var sendButton: some View {
        Button(action: submitEvent) {
            ZStack {
                Text(Strings.Event.sendSignal)
                    .font(.blipperUI(.headline, weight: 600))
                    // Hidden rather than removed, so the button doesn't resize
                    // around the spinner mid-send.
                    .opacity(viewModel.isLoading ? 0 : 1)

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Blipper.onAmber)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            // The one filled-amber surface in the app. Amber is otherwise the
            // event icon's outline and nothing else, and this is the button
            // that turns what you've built into one of those icons — so it's
            // the signal's own colour, not the chrome's. Inert until there's
            // something to send, where it drops back to a plain surface.
            .background(
                isArmed ? Blipper.amber : Blipper.surface,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(isArmed ? Blipper.onAmber : Blipper.textMuted)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isArmed ? .clear : Blipper.hairline, lineWidth: 1)
            )
            // The pulse the lines used to carry, moved into the haze: the
            // button holds still and its light breathes, which survives being
            // a solid shape where an opacity pulse would just read as a
            // flickering control.
            .blipperGlow(Blipper.amber, radius: pulseRadius, opacity: pulseOpacity)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isPulsing
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .frame(width: 280)
        .padding(.vertical, 16)
        .onAppear(perform: restartPulse)
        // The glow's endpoints move when the button goes live, and a
        // repeatForever animation already in flight won't pick that up — it
        // has to be started again against the new pair.
        .onChange(of: canSubmit) { _, _ in restartPulse() }
    }

    // Nothing to send: dark. Sending: a steady low light, so the button stops
    // competing with the icon that's flaring above it. Otherwise: breathing.
    private var pulseRadius: CGFloat {
        guard isArmed else { return 0 }
        guard canSubmit else { return 12 }
        return isPulsing ? 26 : 10
    }

    private var pulseOpacity: Double {
        guard isArmed else { return 0 }
        guard canSubmit else { return 0.3 }
        return isPulsing ? 0.6 : 0.25
    }

    private func restartPulse() {
        isPulsing = false
        DispatchQueue.main.async { isPulsing = true }
    }

    private func submitEvent() {
        guard canSubmit else { return }
        // Lights before the write is even sent, so the flare answers the tap
        // rather than the network.
        withAnimation(.easeOut(duration: 0.3)) { flare = 1 }

        Task {
            // Started before the submit rather than awaited after it, so the
            // dwell and the write overlap: a slow write is never made slower,
            // and a fast one still gets the full moment on screen.
            let dwell = Task { try? await Task.sleep(for: flareDwell) }
            await viewModel.submit()
            await dwell.value

            if viewModel.didCreate {
                dismiss()
            } else {
                // Failed. Put the icon out again so the error underneath it is
                // the thing being looked at.
                withAnimation(.easeOut(duration: 0.25)) { flare = 0 }
            }
        }
    }

    private var whoPicker: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    AudienceCard(
                        title: Strings.Event.allFriendsLabel,
                        emoji: nil,
                        systemImage: "person.3.fill",
                        isSelected: viewModel.selectedGroupIds.isEmpty
                    ) {
                        viewModel.selectedGroupIds.removeAll()
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 12) {
                        ForEach(viewModel.groups) { group in
                            AudienceCard(
                                title: group.name,
                                emoji: group.emoji,
                                systemImage: "person.2.fill",
                                isSelected: group.id.map { viewModel.selectedGroupIds.contains($0) } ?? false
                            ) {
                                toggleGroup(group)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .frame(minWidth: geo.size.width)
            }
        }
        .frame(height: 100)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func toggleGroup(_ group: FriendGroup) {
        guard let id = group.id else { return }
        if viewModel.selectedGroupIds.contains(id) {
            viewModel.selectedGroupIds.remove(id)
        } else {
            viewModel.selectedGroupIds.insert(id)
        }
    }
}

// AudienceCard moved to EventFormControls.swift, which the edit sheets can
// reach as well — they show the same cards as a record of who a signal went to.
