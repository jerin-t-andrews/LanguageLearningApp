//
//  LanguageLearningAppApp.swift
//  LanguageLearningApp
//
//  Created by Jerin Andrews on 2/2/25.
//

import SwiftUI

@main
struct LanguageLearningAppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
