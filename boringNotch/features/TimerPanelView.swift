//
//  TimerPanelView.swift
//  boringNotch
//
//  Tools: timer and stopwatch panel.
//

import Defaults
import SwiftUI

struct TimerPanelView: View {
    @ObservedObject var manager = TimerManager.shared
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Text(manager.mode == .timer ? "Timer" : "Stopwatch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            Picker("", selection: $manager.mode) {
                Text("Timer").tag(TimerMode.timer)
                Text("Stopwatch").tag(TimerMode.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            Text(displayText)
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .foregroundStyle(displayColour)
                .frame(maxWidth: .infinity)

            controls
        }
        .padding(.top, 14)
        .padding(.bottom, 26)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var displayText: String {
        switch manager.mode {
        case .timer:
            return TimerManager.format(manager.timerRemaining)
        case .stopwatch:
            return TimerManager.format(manager.stopwatchElapsed)
        }
    }

    private var displayColour: Color {
        if manager.mode == .timer, manager.timerFinished { return .red }
        return .white
    }

    @ViewBuilder
    private var controls: some View {
        switch manager.mode {
        case .timer:
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Stepper(
                        "Minutes: \(Int(manager.timerDuration) / 60)",
                        value: Binding(
                            get: { Int(manager.timerDuration) / 60 },
                            set: { manager.setTimerMinutes($0) }
                        ),
                        in: 1...600,
                        step: 1
                    )
                    .disabled(manager.timerRunning)
                    .labelsHidden()
                    .frame(width: 40)

                    Text("\(Int(manager.timerDuration) / 60) min")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .frame(width: 52, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Button(manager.timerRunning ? "Pause" : "Start") {
                        manager.timerRunning ? manager.pauseTimer() : manager.startTimer()
                    }
                    Button("Reset") {
                        manager.resetTimer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
            }
        case .stopwatch:
            HStack(spacing: 8) {
                Button(manager.stopwatchRunning ? "Stop" : "Start") {
                    manager.stopwatchRunning ? manager.pauseStopwatch() : manager.startStopwatch()
                }
                Button("Reset") {
                    manager.resetStopwatch()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white)
        }
    }
}
