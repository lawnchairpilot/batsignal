import SwiftUI

struct AddFriendView: View {
    @ObservedObject var viewModel: FriendsViewModel
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("+1 (555) 000-0000", text: $viewModel.searchPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                Button(action: { Task { await viewModel.searchByPhone(currentUserId: authService.currentUser?.id) } }) {
                    Text("Search")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.searchPhone.isEmpty || viewModel.isLoading)

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                if let user = viewModel.searchResult {
                    let alreadyFriend = viewModel.friends.contains { $0.id == user.id }
                    let pendingRequest = user.id.map { viewModel.hasPendingOutgoingRequest(toUserId: $0) } ?? false
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.displayName).font(.headline)
                            Text(user.phoneNumber).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if alreadyFriend {
                            Text("Friends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if pendingRequest {
                            Text("Requested")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Button("Add") {
                                Task {
                                    guard let id = user.id else { return }
                                    await viewModel.sendRequest(toUserId: id)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
