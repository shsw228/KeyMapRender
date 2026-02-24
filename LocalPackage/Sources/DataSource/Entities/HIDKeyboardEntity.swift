import Foundation

public struct HIDKeyboardDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let vendorID: Int
    public let productID: Int
    public let locationID: Int
    public let productName: String
    public let manufacturerName: String

    public init(
        id: String,
        vendorID: Int,
        productID: Int,
        locationID: Int,
        productName: String,
        manufacturerName: String
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.productName = productName
        self.manufacturerName = manufacturerName
    }
}
