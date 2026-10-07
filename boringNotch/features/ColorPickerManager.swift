//
//  ColorPickerManager.swift
//  boringNotch
//
//  Tools: screen colour picker. Uses the system sampler (NSColorSampler),
//  no screen recording permission required. Copies the hex value.
//

import AppKit
import Defaults
import SwiftUI

final class ColorPickerManager: ObservableObject {
    static let shared = ColorPickerManager()

    @Published var recent: [String] = Defaults[.colorPickerRecent]

    private init() {}

    func pick() {
        let sampler = NSColorSampler()
        sampler.show { colour in
            guard let colour else { return }
            let hex = self.hexString(colour)
            self.copy(hex)
        }
    }

    func copy(_ hex: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)

        var recent = Defaults[.colorPickerRecent].filter { $0 != hex }
        recent.insert(hex, at: 0)
        if recent.count > 8 {
            recent.removeLast(recent.count - 8)
        }
        Defaults[.colorPickerRecent] = recent
        self.recent = recent
    }

    func colour(from hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return .gray }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    private func hexString(_ colour: NSColor) -> String {
        guard let srgb = colour.usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(srgb.redComponent * 255)),
            Int(round(srgb.greenComponent * 255)),
            Int(round(srgb.blueComponent * 255))
        )
    }
}
