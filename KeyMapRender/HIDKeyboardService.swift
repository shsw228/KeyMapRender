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

        return set.compactMap(makeDeviceInfo).sorted {
            if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
            if $0.productID != $1.productID { return $0.productID < $1.productID }
            return $0.productName < $1.productName
        }
    }

    nonisolated static func findRawHIDInterface(for keyboard: HIDKeyboardDevice) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let rawMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0xFF60,
            kIOHIDDeviceUsageKey as String: 0x61
        ]
        IOHIDManagerSetDeviceMatching(manager, rawMatch as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }

        return set.first(where: { device in
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
        })
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
}
