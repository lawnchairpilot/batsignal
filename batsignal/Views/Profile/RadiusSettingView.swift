import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RadiusSettingView: View {
    @EnvironmentObject var authService: AuthService
    @State private var selectedRadius: Double? = nil

    private let options: [(label: String, value: Double?)] = [
        ("No limit", nil),
        ("10 miles", 10),
        ("25 miles", 25),
        ("50 miles", 50),
        ("100 miles", 100),
    ]

    var body: some View {
        List {
            ForEach(options, id: \.label) { option in
                Button(action: { select(option.value) }) {
                    HStack {
                        Text(option.label)
                        Spacer()
                        if selectedRadius == option.value {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .navigationTitle("Event Radius")
        .onAppear {
            selectedRadius = authService.currentUser?.maxEventRadius
        }
    }

    private func select(_ value: Double?) {
        selectedRadius = value
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = value != nil
            ? ["maxEventRadius": value!]
            : ["maxEventRadius": FieldValue.delete()]
        Firestore.firestore().collection("users").document(uid).updateData(data)
    }
}
