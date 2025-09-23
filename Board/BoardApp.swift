//
//  BoardApp.swift
//  Board
//
//  Created by Ananjan Mitra on 23/09/25.
//

import SwiftUI

@main
struct BoardApp: App {
    var body: some Scene {
        MenuBarExtra("Board", systemImage: "clipboard") {
            MenuView()
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView()
        }
    }
}
