import Foundation

// App-target bridge between the IOKit probe in GestaltAccess and the pure
// DeviceIdentityAudit logic in GestaltModels.swift. Kept in its own file so
// the logic test harness (which compiles GestaltModels.swift without the
// bridging header) can build without linking the ObjC probe.
enum IdentityProbe {
    /// SoC platform name from the IOKit device tree, e.g. "t8130". This value
    /// comes from the hardware itself and cannot be changed by cache edits.
    static var ioKitPlatformName: String? {
        guard let cfName = GestaltIOKitPlatformName() else { return nil }
        defer { cfName.release() }
        let name = cfName as String
        return name.isEmpty ? nil : name
    }

    /// Board configuration from the kernel, e.g. "D17AP". On iOS the hw.model
    /// sysctl reports the board configuration string used by MobileGestalt's
    /// HardwareModel / TargetSubType and HWModelStr questions.
    static var kernelHardwareModel: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return nil }
        let model = String(cString: value)
        return model.isEmpty ? nil : model
    }
}
