//
//  ToolsView.swift
//  boringNotch
//
//  Tools tab: quick utility tiles (eject, caffeinate, timer, colour picker).
//  Heavier features (clipboard history, performance stats) get their own tabs.
//

import Defaults
import SwiftUI

enum ToolsPage: Equatable {
    case grid
    case eject
    case timer
}

struct ToolsView: View {
    @State private var page: ToolsPage = .grid

    var body: some View {
        Group {
            switch page {
            case .grid:
                grid
            case .eject:
                Text("Eject panel")
            case .timer:
                Text("Timer panel")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.25), value: page)
    }

    private var grid: some View {
        VStack(spacing: 10) {
            Text("Tools")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                if Defaults[.featureDiskEject] {
                    ToolTile(icon: "externaldrive.fill", label: "Eject") {
                        page = .eject
                    }
                }
                if Defaults[.featureCaffeinate] {
                    ToolTile(icon: "cup.and.saucer.fill", label: "Caffeinate") {}
                }
                if Defaults[.featureTimer] {
                    ToolTile(icon: "timer", label: "Timer") {
                        page = .timer
                    }
                }
                if Defaults[.featureColorPicker] {
                    ToolTile(icon: "eyedropper", label: "Pick colour") {}
                }
            }

            if !hasTiles {
                Text("Every tool is off. Enable them in Settings, Tools.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    private var hasTiles: Bool {
        Defaults[.featureDiskEject] || Defaults[.featureCaffeinate]
            || Defaults[.featureTimer] || Defaults[.featureColorPicker]
    }
}

struct ToolTile: View {
    let icon: String
    let label: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? Color.white.opacity(0.45) : Color.white.opacity(0.12))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
