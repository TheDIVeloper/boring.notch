//
//  CaffeinateManager.swift
//  boringNotch
//
//  Tools: keep the Mac awake with a power management assertion.
//

import Foundation
import IOKit.pwr_mgt

final class CaffeinateManager: ObservableObject {
    static let shared = CaffeinateManager()

    @Published var isOn = false
    private var assertionID = IOPMAssertionID(0)

    private init() {}

    func setCaffeinated(_ on: Bool) {
        if on {
            guard assertionID == 0 else { return }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Notch caffeinate" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
                isOn = true
            }
        } else if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
            isOn = false
        }
    }

    func toggle() {
        setCaffeinated(!isOn)
    }
}
