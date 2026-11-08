// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Foundation

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Focused/main window of a running app.
    static func mainWindow(of app: NSRunningApplication) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &v) == .success,
           let w = v { return (w as! AXUIElement) }
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &v) == .success,
           let arr = v as? [AXUIElement], let first = arr.first { return first }
        if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &v) == .success,
           let w = v { return (w as! AXUIElement) }
        return nil
    }

    static func getPoint(_ win: AXUIElement, _ attr: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, attr as CFString, &v) == .success, let value = v else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &p) else { return nil }
        return p
    }

    static func getSize(_ win: AXUIElement, _ attr: String) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, attr as CFString, &v) == .success, let value = v else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &s) else { return nil }
        return s
    }

    static func setPosition(_ win: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) == .success
    }

    static func setSize(_ win: AXUIElement, _ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) == .success
    }

    /// Visible frame in AX coordinates (top-left origin) for the screen containing `point`.
    static func visibleFrameAX(containing p: CGPoint) -> CGRect {
        // Primary display height (Cocoa origin (0,0) = bottom-left of screens[0]);
        // AX y is measured from the top of that primary display.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let screen = NSScreen.screens.first { scr in
            let cocoaY = primaryH - p.y
            return NSPointInRect(NSPoint(x: p.x, y: cocoaY), scr.frame)
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        let axY = primaryH - (v.origin.y + v.height)
        return CGRect(x: v.origin.x, y: axY, width: v.width, height: v.height)
    }
}
