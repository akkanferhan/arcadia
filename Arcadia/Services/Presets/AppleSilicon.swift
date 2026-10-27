import Foundation
import IOKit

/// The Mac's Apple chip, used to pick graphics settings.
struct AppleSilicon {
    /// e.g. "Apple M2 Pro".
    let name: String
    let gpuCores: Int
    let performanceCores: Int
    let memoryGB: Int

    static let current = AppleSilicon()

    private init() {
        name = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        gpuCores = Self.gpuCoreCount() ?? 8
        performanceCores = Self.sysctlInt("hw.perflevel0.physicalcpu") ?? 4
        memoryGB = Int((Self.sysctlInt("hw.memsize") ?? 8 << 30) >> 30)
    }

    /// The upscale factor that keeps demanding systems smooth on this GPU.
    var recommendedScale: Int {
        switch gpuCores {
        case ..<11: 2   // M1–M5 base chips
        case ..<25: 3   // Pro chips
        default: 4      // Max and Ultra chips
        }
    }

    private static func gpuCoreCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? Int
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// The one graphics setting Arcadia exposes; every emulator's resolution follows it.
enum GraphicsQuality: String, CaseIterable, Identifiable {
    case automatic, performance, balanced, quality

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .performance: "Performance"
        case .balanced: "Balanced"
        case .quality: "Best Quality"
        }
    }

    /// Internal resolution multiplier for 3D systems (1 = original console resolution).
    var scale: Int {
        switch self {
        case .automatic: AppleSilicon.current.recommendedScale
        case .performance: 1
        case .balanced: 2
        case .quality: 4
        }
    }
}
