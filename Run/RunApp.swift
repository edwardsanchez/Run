//
//  RunApp.swift
//  Run
//
//  Created by Edward Sanchez on 8/19/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct RunApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: RunMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct RunMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        RunVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct RunVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
