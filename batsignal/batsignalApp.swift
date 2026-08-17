//
//  batsignalApp.swift
//  batsignal
//
//  Created by Aiden Drugge on 4/12/26.
//

import SwiftUI
import FirebaseAuth

@main
struct batsignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoadingUser {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !authService.isAuthenticated {
                    AuthFlowView()
                        .environmentObject(authService)
                } else if authService.needsProfileSetup {
                    ProfileSetupView()
                        .environmentObject(authService)
                } else if authService.currentUser?.acceptedTermsAt == nil {
                    // Sits after profile setup so there's a document to record
                    // the acceptance on, and before Root so nothing can be
                    // posted or read until the rules have been agreed to.
                    CommunityRulesView()
                } else {
                    RootView()
                        .environmentObject(authService)
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth {
                    NotificationService.shared.requestPermissionAndRefresh()
                }
            }
            .onOpenURL { url in
                _ = Auth.auth().canHandle(url)
            }
        }
    }
}
