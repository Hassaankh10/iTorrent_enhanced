//
//  AppDelegate+Firebase.swift
//  iTorrent
//
//  Created by Даниил Виноградов on 20.04.2024.
//

import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

extension AppDelegate {
    func registerFirebase() {
#if canImport(FirebaseCore)
        FirebaseApp.configure()
#endif
#if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
#endif
    }
}
