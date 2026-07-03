//
//  TimeClockBarApp.swift
//  TimeClockBar
//
//  Created by Van AJ Vanguardia on 7/3/26.
//

import SwiftUI

@main
struct TimeClockBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
