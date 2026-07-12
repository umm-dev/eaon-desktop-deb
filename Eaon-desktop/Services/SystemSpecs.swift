import Darwin
import Foundation

/// Real hardware facts about this Mac — used to judge whether a model will
/// actually fit and run before the user spends minutes (or hours) downloading
/// it to find out the hard way.
enum SystemSpecs {
    /// Total installed RAM. A hardware constant — doesn't change while running.
    static var totalMemory: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    /// RAM actually free right now (free + inactive + purgeable + speculative
    /// pages — the same reclaimable categories Activity Monitor's "Memory
    /// Used" excludes) via the Mach host_statistics64 API. Unlike
    /// `totalMemory`, this changes as other apps run.
    static var availableMemory: Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        // A failed syscall shouldn't crash a fit estimate — fall back to a
        // conservative "half of total" guess rather than reporting 0 (which
        // would wrongly flag everything as too big).
        guard result == KERN_SUCCESS else { return totalMemory / 2 }
        let pageSize = Int64(vm_kernel_page_size)
        return (Int64(stats.free_count) + Int64(stats.inactive_count)
                 + Int64(stats.purgeable_count) + Int64(stats.speculative_count)) * pageSize
    }

    /// Whether this Mac is Apple Silicon — matters because MLX requires it
    /// outright, and because Metal-accelerated llama.cpp/Ollama are far
    /// faster on unified memory than on an Intel Mac's discrete/CPU path.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }

    /// Free disk space "for important usage" — a bit more realistic than a
    /// raw free-bytes count since it reflects what's genuinely reclaimable,
    /// not space already earmarked by the system.
    static var freeDiskSpace: Int64 {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return capacity
    }

    // MARK: - Settings → Hardware display

    /// Human-readable chip name, e.g. "Apple M5" — verified live that
    /// `machdep.cpu.brand_string` returns this on Apple Silicon (it used to
    /// only cover Intel on older macOS), so this needed no Apple Silicon
    /// special-case or model-identifier lookup table.
    static var cpuModel: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer).trimmingCharacters(in: .whitespaces)
    }

    /// Every Mac since the Intel→Apple Silicon transition is one or the
    /// other — no Rosetta special-case needed since this reads the host's
    /// actual hardware capability flag, not the running process's own
    /// translated architecture.
    static var architecture: String {
        isAppleSilicon ? "arm64" : "x86_64"
    }

    static var cpuCoreCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    /// "macOS 26.5.2" — built from the numeric version rather than
    /// `operatingSystemVersionString`, which includes a build number Jan's
    /// own display doesn't show ("Version 26.5.2 (Build 25F84)").
    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// Live CPU usage, sampled as a delta between two `host_statistics` reads
/// rather than one instantaneous call — the kernel only exposes cumulative
/// tick counts since boot, so "usage right now" is inherently a rate
/// computed over a short window. One instance per view; call `sample()` on
/// a timer (every ~2s is enough to be responsive without churning the CPU
/// itself) and ignore the first call, which has no prior sample to diff
/// against.
final class CPULoadSampler {
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// Percentage 0–100, or nil on the first call or if the syscall fails.
    func sample() -> Double? {
        guard let ticks = Self.readTicks() else { return nil }
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return nil }

        let user = Double(ticks.user &- last.user)
        let system = Double(ticks.system &- last.system)
        let idle = Double(ticks.idle &- last.idle)
        let nice = Double(ticks.nice &- last.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total * 100
    }

    private static func readTicks() -> (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
    }
}

// MARK: - Fit estimate

enum ModelFitVerdict: Equatable {
    case comfortable
    case tight
    case tooBig
}

struct ModelFitEstimate: Equatable {
    let verdict: ModelFitVerdict
    /// Short label for the badge itself, e.g. "Runs comfortably".
    let headline: String
    /// The reasoning behind the verdict, in plain language with the actual
    /// numbers — shown on hover so the claim is never just a black box.
    let detail: String
}

/// Judges whether a model will fit and run on this Mac from its real
/// download size — an estimate, clearly labeled as one, not a promise:
/// exact RAM needs vary with context length and how a backend manages
/// memory, which nothing short of actually running the model can tell you
/// for certain.
enum ModelFitEstimator {
    private static func format(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return gb < 10 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }

    static func assess(downloadSizeBytes: Int64, backend: LocalBackend) -> ModelFitEstimate {
        guard downloadSizeBytes > 0 else {
            return ModelFitEstimate(verdict: .tight, headline: "Size unknown", detail: "Couldn't determine this model's size ahead of time.")
        }

        if backend == .mlx, !SystemSpecs.isAppleSilicon {
            return ModelFitEstimate(
                verdict: .tooBig,
                headline: "Needs Apple Silicon",
                detail: "MLX models only run on Apple Silicon Macs (M1 or later). This Mac has an Intel processor."
            )
        }

        // Rule of thumb (not exact — real usage varies with context length
        // and quantization): a loaded model needs roughly its own file size
        // in RAM, plus overhead for the runtime and context/KV cache. The
        // 25%-or-2GB floor keeps small models from getting an unrealistically
        // thin margin (a 500MB model still needs real headroom for the OS).
        let overhead = max(2_000_000_000, Int64(Double(downloadSizeBytes) * 0.25))
        let requiredRAM = downloadSizeBytes + overhead
        let requiredDiskWithMargin = Int64(Double(downloadSizeBytes) * 1.1)

        let totalRAM = SystemSpecs.totalMemory
        let availableRAM = SystemSpecs.availableMemory
        let freeDisk = SystemSpecs.freeDiskSpace

        if freeDisk < downloadSizeBytes {
            return ModelFitEstimate(
                verdict: .tooBig,
                headline: "Not enough disk",
                detail: "Needs \(format(downloadSizeBytes)) — you have \(format(freeDisk)) free."
            )
        }
        if totalRAM < requiredRAM {
            return ModelFitEstimate(
                verdict: .tooBig,
                headline: "Too big for this Mac",
                detail: "Needs roughly \(format(requiredRAM)) of RAM to run — this Mac has \(format(totalRAM)) total, so it won't fit no matter what else is closed."
            )
        }
        if availableRAM < requiredRAM || freeDisk < requiredDiskWithMargin {
            return ModelFitEstimate(
                verdict: .tight,
                headline: "Might be tight",
                detail: "Needs roughly \(format(requiredRAM)) of RAM — you have \(format(availableRAM)) free right now out of \(format(totalRAM)) total. Closing other apps first may help."
            )
        }
        return ModelFitEstimate(
            verdict: .comfortable,
            headline: "Fits well",
            detail: "Needs roughly \(format(requiredRAM)) of RAM — you have \(format(availableRAM)) free right now."
        )
    }
}
