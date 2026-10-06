import AppKit

// Text owns its drawing instead of participating in the menu's vibrant blending.
// These read-only labels expose static text, including in a custom menu row.
@MainActor
final class MenuTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
}
