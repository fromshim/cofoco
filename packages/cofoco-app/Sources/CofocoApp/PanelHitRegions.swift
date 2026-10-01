import Foundation

enum PanelHitRegions {
    static func contains(_ point: CGPoint, width: CGFloat, height: CGFloat, bubbleVisible: Bool,
                         mainHeight: CGFloat, changeHeight: CGFloat?) -> Bool {
        let pet = CGRect(x: width - 122, y: 10, width: 112, height: 112)
        if pet.contains(point) { return true }
        guard bubbleVisible else { return false }
        let main = CGRect(x: width - 334, y: 130, width: 324, height: mainHeight)
        if main.contains(point) { return true }
        if let changeHeight {
            let change = CGRect(x: width - 334, y: height - 10 - changeHeight, width: 324, height: changeHeight)
            return change.contains(point)
        }
        return false
    }
}
