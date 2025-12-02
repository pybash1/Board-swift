import SwiftUI

@main
struct BoardApp: App {
    @StateObject private var viewModel = BoardViewModel()
    
    init() {
        // Initially hide dock icon - only show when settings window is open
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    
    var body: some Scene {
        MenuBarExtra("Board", image: "MenuBarIcon") {
            MenuBarContentView()
                .environmentObject(viewModel)
        }
        
        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}