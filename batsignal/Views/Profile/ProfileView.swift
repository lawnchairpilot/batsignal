import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        EventIconView(
                            photoURL: authService.currentUser?.profilePhotoURL,
                            label: initials,
                            size: 60
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authService.currentUser?.displayName ?? "")
                                .font(.headline)
                            Text(authService.currentUser?.phoneNumber ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section(Strings.Profile.preferencesSection) {
                    NavigationLink(Strings.Profile.eventRadiusFilter) {
                        RadiusSettingView()
                    }
                }

                Section {
                    Button(Strings.Profile.signOut, role: .destructive) {
                        try? authService.signOut()
                    }
                }
            }
            .navigationTitle(Strings.Profile.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(Strings.Profile.edit) { showEditProfile = true }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
        }
    }

    private var initials: String? {
        guard let name = authService.currentUser?.displayName, !name.isEmpty else { return nil }
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return parts.isEmpty ? nil : parts.uppercased()
    }
}