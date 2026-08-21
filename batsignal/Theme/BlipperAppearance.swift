import UIKit

// Navigation bars, sheets, and the rest of the UIKit chrome underneath SwiftUI
// don't read the SwiftUI palette, so they're dressed once at launch. Without
// this the bars keep their default system materials and grays, which read as
// light patches against the dusk gradient.
enum BlipperAppearance {

    static func apply() {
        let title = UIColor(hex: 0xEAEEEF)      // Moonlight White
        let chrome = UIColor(hex: 0xC7D0D4)     // Muffled Moonlight
        let accent = UIColor(hex: 0xFFD35C)     // Harbor Light Amber
        let base = UIColor(hex: 0x16283A)       // Dusk Navy

        let navigation = UINavigationBarAppearance()
        // Transparent rather than filled, so the gradient behind the content
        // runs up under the bar instead of stopping at a flat block of navy.
        navigation.configureWithTransparentBackground()
        navigation.backgroundColor = .clear
        navigation.shadowColor = .clear
        // Inter, not the display face: a navigation title names the screen, not the app,
        // and the wordmark is the only place the display face earns its keep.
        navigation.titleTextAttributes = [
            .foregroundColor: title,
            .font: BlipperFont.uiFont(BlipperFont.ui, size: BlipperFont.baseSize(for: .headline), weight: 600),
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: title,
            .font: BlipperFont.uiFont(BlipperFont.ui, size: BlipperFont.baseSize(for: .largeTitle), weight: 600),
        ]
        // Back and bar buttons are navigation, not identity — Inter, and amber
        // because they're actions.
        let button = UIBarButtonItemAppearance(style: .plain)
        button.normal.titleTextAttributes = [
            .foregroundColor: accent,
            .font: BlipperFont.uiFont(BlipperFont.ui, size: BlipperFont.baseSize(for: .body), weight: 500),
        ]
        navigation.buttonAppearance = button
        navigation.backButtonAppearance = button
        navigation.doneButtonAppearance = button

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = navigation
        bar.scrollEdgeAppearance = navigation
        bar.compactAppearance = navigation
        bar.tintColor = accent

        // Grouped tables sit on the gradient, so their own backdrop has to go —
        // the cards drawn on top carry the surface color themselves.
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear

        UISwitch.appearance().onTintColor = accent
        UIToolbar.appearance().tintColor = accent

        let search = UISearchBar.appearance()
        search.tintColor = accent
        search.searchTextField.textColor = title
        search.searchTextField.backgroundColor = base.withAlphaComponent(0.55)

        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = chrome.withAlphaComponent(0.3)

        UIRefreshControl.appearance().tintColor = chrome
    }
}
