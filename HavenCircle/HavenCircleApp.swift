//
//  HavenCircleApp.swift
//  HavenCircle
//
//  Created by Harry Hwa on 2026/7/15.
//

import SwiftUI
import SwiftData

@main
struct HavenCircleApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([LocalSafetyEvent.self, LocalFamilyMember.self, LocalLifeCircle.self])
        let configuration = ModelConfiguration(schema: schema)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { DemoSeed.insertIfNeeded(into: modelContainer.mainContext) }
        }
        .modelContainer(modelContainer)
    }
}
