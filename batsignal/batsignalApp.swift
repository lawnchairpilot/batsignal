//
//  batsignalApp.swift
//  batsignal
//
//  Created by Aiden Drugge on 4/12/26.
//

import SwiftUI
import FirebaseCore

@main
struct batsignalApp: App {
    @StateObject private var authService = AuthService.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated && authService.currentUser != nil {
                MainTabView()
                    .environmentObject(authService)
            } else {
                AuthFlowView()
                    .environmentObject(authService)
            }
        }
    }
}
