//
//  Reciprocity_Failure_CalculatorApp.swift
//  Reciprocity Failure Calculator
//
//  Created by Baker Moran on 2/10/25.
//

import SwiftUI

@main
struct Reciprocity_Failure_CalculatorApp: App {
    @State private var store = FilmStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

private struct RootView: View {
    @AppStorage("selectedTab") private var tab = "reciprocity"

    var body: some View {
        TabView(selection: $tab) {
            Tab("Reciprocity", systemImage: "hourglass", value: "reciprocity") {
                ContentView()
            }
            Tab("Meter", systemImage: "camera.metering.spot", value: "meter") {
                MeterView()
            }
            Tab("Flash", systemImage: "bolt", value: "flash") {
                FlashView()
            }
        }
    }
}
