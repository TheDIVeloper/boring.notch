//
//  TimerManager.swift
//  boringNotch
//
//  Tools: countdown timer and stopwatch. Lives as a singleton so it keeps
//  running while the notch is closed; fires a notification on finish.
//

import Foundation
import UserNotifications

enum TimerMode: String, CaseIterable {
    case timer
    case stopwatch
}

final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published var mode: TimerMode = .timer

    @Published var timerDuration: TimeInterval = 300
    @Published var timerRemaining: TimeInterval = 300
    @Published var timerRunning = false
    @Published var timerFinished = false

    @Published var stopwatchElapsed: TimeInterval = 0
    @Published var stopwatchRunning = false

    private var ticker: Timer?
    private var timerEndDate: Date?
    private var stopwatchStartDate: Date?
    private var stopwatchBase: TimeInterval = 0
    private var notificationRequested = false

    private init() {}

    // MARK: Countdown

    func setTimerMinutes(_ minutes: Int) {
        guard !timerRunning else { return }
        let clamped = max(1, minutes)
        timerDuration = TimeInterval(clamped * 60)
        timerRemaining = timerDuration
        timerFinished = false
    }

    func startTimer() {
        guard !timerRunning else { return }
        if timerRemaining <= 0 {
            timerRemaining = timerDuration
        }
        timerFinished = false
        timerEndDate = Date().addingTimeInterval(timerRemaining)
        timerRunning = true
        requestNotificationAuthIfNeeded()
        startTicker()
    }

    func pauseTimer() {
        guard timerRunning else { return }
        timerRemaining = max(0, timerEndDate?.timeIntervalSinceNow ?? timerRemaining)
        timerRunning = false
        timerEndDate = nil
        stopTickerIfIdle()
    }

    func resetTimer() {
        timerRunning = false
        timerEndDate = nil
        timerFinished = false
        timerRemaining = timerDuration
        stopTickerIfIdle()
    }

    // MARK: Stopwatch

    func startStopwatch() {
        guard !stopwatchRunning else { return }
        stopwatchStartDate = Date()
        stopwatchRunning = true
        startTicker()
    }

    func pauseStopwatch() {
        guard stopwatchRunning else { return }
        stopwatchBase += stopwatchStartDate?.timeIntervalSinceNow ?? 0
        stopwatchElapsed = stopwatchBase
        stopwatchStartDate = nil
        stopwatchRunning = false
        stopTickerIfIdle()
    }

    func resetStopwatch() {
        stopwatchRunning = false
        stopwatchStartDate = nil
        stopwatchBase = 0
        stopwatchElapsed = 0
        stopTickerIfIdle()
    }

    // MARK: Ticking

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTickerIfIdle() {
        if !timerRunning && !stopwatchRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        if timerRunning, let endDate = timerEndDate {
            let remaining = endDate.timeIntervalSinceNow
            if remaining <= 0 {
                timerRemaining = 0
                timerRunning = false
                timerFinished = true
                timerEndDate = nil
                stopTickerIfIdle()
                notifyFinished()
            } else {
                timerRemaining = remaining
            }
        }
        if stopwatchRunning, let startDate = stopwatchStartDate {
            stopwatchElapsed = stopwatchBase + startDate.timeIntervalSinceNow
        }
    }

    // MARK: Display

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: Notifications

    private func requestNotificationAuthIfNeeded() {
        guard !notificationRequested else { return }
        notificationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyFinished() {
        let content = UNMutableNotificationContent()
        content.title = "Timer finished"
        content.body = "Your countdown has ended."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
