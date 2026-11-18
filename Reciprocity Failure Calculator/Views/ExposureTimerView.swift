//
//  ExposureTimerView.swift
//  Reciprocity Failure Calculator
//

import AudioToolbox
import SwiftUI
import UserNotifications

/// Countdown for a long exposure. Keeps the screen awake while running and schedules a
/// local notification so the end is announced even if the app is in the background.
struct ExposureTimerView: View {
    let duration: Double
    let filmName: String

    @Environment(\.dismiss) private var dismiss
    @State private var endDate: Date?
    @State private var pausedRemaining: Double?
    @State private var finished = false

    private static let notificationID = "exposure-timer"

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let remaining = remaining(at: context.date)
                VStack(spacing: 32) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: remaining / duration)
                            .stroke(finished ? Color.green : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 4) {
                            Text(finished ? String(localized: "Done") : ExposureFormat.clock(fromSeconds: remaining))
                                .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                            Text("of \(ExposureFormat.string(fromSeconds: duration))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 300)
                    .padding()

                    controls
                }
                .padding()
                .onChange(of: remaining <= 0) { _, done in
                    if done, endDate != nil { finish() }
                }
            }
            .navigationTitle(filmName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onDisappear(perform: stop)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 24) {
            Button("Reset", action: reset)
                .buttonStyle(.bordered)
                .disabled(endDate == nil && pausedRemaining == nil && !finished)

            if endDate != nil {
                Button("Pause", action: pause).buttonStyle(.borderedProminent).tint(.orange)
            } else if !finished {
                Button(pausedRemaining == nil ? "Start" : "Resume", action: start)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }

    private func remaining(at date: Date) -> Double {
        if finished { return 0 }
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration
    }

    private func start() {
        let seconds = pausedRemaining ?? duration
        endDate = .now.addingTimeInterval(seconds)
        pausedRemaining = nil
        finished = false
        UIApplication.shared.isIdleTimerDisabled = true
        scheduleNotification(in: seconds)
    }

    private func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        cancelNotification()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func reset() {
        stop()
        pausedRemaining = nil
        finished = false
    }

    private func finish() {
        endDate = nil
        finished = true
        UIApplication.shared.isIdleTimerDisabled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1005)
    }

    private func stop() {
        endDate = nil
        cancelNotification()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func scheduleNotification(in seconds: Double) {
        let center = UNUserNotificationCenter.current()
        let title = filmName
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Exposure complete")
            content.body = String(localized: "\(title): close the shutter.")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
}

#Preview {
    ExposureTimerView(duration: 95, filmName: "Ilford HP5+")
}
