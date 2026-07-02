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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService.shared

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .environmentObject(authService)
                } else {
                    AuthFlowView()
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
