// GodsWordApp.swift
import SwiftUI

@main
struct GodsWordApp: App {
    @StateObject private var personalData = PersonalData()
    @StateObject private var driveBackup = GoogleDriveBackup()
    private let moduleStore = ModuleStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(personalData)
                .environmentObject(driveBackup)
                .environment(\.moduleStore, moduleStore)
        }
    }
}

// ModuleStore passed via environment key (it is not ObservableObject).
private struct ModuleStoreKey: EnvironmentKey {
    static let defaultValue = ModuleStore()
}

extension EnvironmentValues {
    var moduleStore: ModuleStore {
        get { self[ModuleStoreKey.self] }
        set { self[ModuleStoreKey.self] = newValue }
    }
}
