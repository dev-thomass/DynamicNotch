//
//  Ext+NSScreen.swift
//  DynamicNotch
//

import Cocoa

extension NSScreen {
    var isBuildinDisplay: Bool {
        let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let id = deviceDescription[screenNumberKey],
              let rid = (id as? NSNumber)?.uint32Value,
              CGDisplayIsBuiltin(rid) == 1
        else { return false }
        return true
    }

    static var buildin: NSScreen? {
        screens.first { $0.isBuildinDisplay }
    }
}
