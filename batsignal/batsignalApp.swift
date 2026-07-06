//
//  batsignalApp.swift
//  batsignal
//
//  Created by Aiden Drugge on 4/12/26.
//

import SwiftUI

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
                } else {
                    MainTabView()
                        .environmentObject(authService)
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth {
                    NotificationService.shared.requestPermissionAndRefresh()
                }
            }
        }
    }
}
