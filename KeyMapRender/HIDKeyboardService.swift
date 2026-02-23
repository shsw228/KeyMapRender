import Foundation
import IOKit.hid

struct HIDKeyboardDevice: Identifiable, Hashable {
    let id: String
    let vendorID: Int
    let productID: Int
    let locationID: Int
    let productName: String
    let manufacturerName: String
}

struct HIDInterfaceCandidate {
    let device: IOHIDDevice
    let usagePage: Int
    let usage: Int
    let productName: String
}

enum HIDKeyboardService {
    nonisolated static func listKeyboards() -> [HIDKeyboardDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        let keypadMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keypad
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, keypadMatch] as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        let deduped = deduplicate(set.compactMap(makeDeviceInfo))
        return deduped.sorted {
            if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
            if $0.productID != $1.productID { return $0.productID < $1.productID }
            return $0.productName < $1.productName
        }
    }

    nonisolated static func findCandidateInterfaces(for keyboard: HIDKeyboardDevice) -> [HIDInterfaceCandidate] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: keyboard.vendorID,
            kIOHIDProductIDKey as String: keyboard.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        let filtered = set.filter { device in
            let vendor = intProperty(device, key: kIOHIDVendorIDKey as CFString)
            let product = intProperty(device, key: kIOHIDProductIDKey as CFString)
            let location = intProperty(device, key: kIOHIDLocationIDKey as CFString)

            if vendor != keyboard.vendorID || product != keyboard.productID {
                return false
            }
            if keyboard.locationID != 0, location != 0 {
                return location == keyboard.locationID
            }
            return true
        }

        let candidates = filtered.map { device in
            HIDInterfaceCandidate(
                device: device,
                usagePage: intProperty(device, key: kIOHIDPrimaryUsagePageKey as CFString),
                usage: intProperty(device, key: kIOHIDPrimaryUsageKey as CFString),
                productName: stringProperty(device, key: kIOHIDProductKey as CFString) ?? "Unknown"
            )
        }

        return candidates.sorted {
            score(candidate: $0) > score(candidate: $1)
        }
    }

    nonisolated private static func makeDeviceInfo(_ device: IOHIDDevice) -> HIDKeyboardDevice? {
        let vendor = intProperty(device, key: kIOHIDVendorIDKey as CFString)
        let product = intProperty(device, key: kIOHIDProductIDKey as CFString)
        guard vendor > 0, product > 0 else { return nil }

        let location = intProperty(device, key: kIOHIDLocationIDKey as CFString)
        let productName = stringProperty(device, key: kIOHIDProductKey as CFString) ?? "Unknown Keyboard"
        let maker = stringProperty(device, key: kIOHIDManufacturerKey as CFString) ?? "Unknown"
        let id = "\(vendor)-\(product)-\(location)"

        return HIDKeyboardDevice(
            id: id,
            vendorID: vendor,
            productID: product,
            locationID: location,
            productName: productName,
            manufacturerName: maker
        )
    }

    nonisolated private static func intProperty(_ device: IOHIDDevice, key: CFString) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return 0 }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return 0
    }

    nonisolated private static func stringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
        IOHIDDeviceGetProperty(device, key) as? String
    }

    nonisolated private static func score(candidate: HIDInterfaceCandidate) -> Int {
        // Prioritize the canonical VIA/Vial Raw HID interface first.
        if candidate.usagePage == 0xFF60 && candidate.usage == 0x61 {
            return 100
        }
        if candidate.usagePage >= 0xFF00 {
            return 50
        }
        return 0
    }

    nonisolated private static func deduplicate(_ devices: [HIDKeyboardDevice]) -> [HIDKeyboardDevice] {
        // Same physical keyboard can appear as multiple HID interfaces.
        var byPhysicalKey: [String: HIDKeyboardDevice] = [:]
        for device in devices {
            let key: String
            if device.locationID != 0 {
                key = "\(device.vendorID)-\(device.productID)-\(device.locationID)"
            } else {
                key = "\(device.vendorID)-\(device.productID)-\(device.manufacturerName)-\(device.productName)"
            }
            if byPhysicalKey[key] == nil {
                byPhysicalKey[key] = device
            }
        }
        return Array(byPhysicalKey.values)
    }
}
