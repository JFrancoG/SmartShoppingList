import UIKit

/// Uses an actual window instance; UIView's tint is not an appearance-proxy property.
final class ShoppingWindowAccentView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        window?.tintColor = UIColor(resource: .nativeAccent)
    }
}
