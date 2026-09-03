import Foundation

struct PipelineLogSignals: Equatable, Sendable {
    var gfxstreamWarningCount = 0
    var asgStallCount = 0
    var vulkanErrorCount = 0
    var moltenVKWarningCount = 0
    var shaderErrorCount = 0
    var fenceTimeoutCount = 0

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            gfxstreamWarningCount: lhs.gfxstreamWarningCount + rhs.gfxstreamWarningCount,
            asgStallCount: lhs.asgStallCount + rhs.asgStallCount,
            vulkanErrorCount: lhs.vulkanErrorCount + rhs.vulkanErrorCount,
            moltenVKWarningCount: lhs.moltenVKWarningCount + rhs.moltenVKWarningCount,
            shaderErrorCount: lhs.shaderErrorCount + rhs.shaderErrorCount,
            fenceTimeoutCount: lhs.fenceTimeoutCount + rhs.fenceTimeoutCount
        )
    }
}

enum TelemetrySignalClassifier {
    /// Counts only lines that identify an actual memory-pressure victim.
    /// LMKD startup, socket, memevent, tracepoint, and policy messages are not kills.
    static func isConfirmedGuestMemoryKill(_ line: String) -> Bool {
        let lower = line.lowercased()

        if lower.contains("out of memory: killed process") {
            return true
        }

        guard lower.contains("lmkd") || lower.contains("lowmemorykiller") else {
            return false
        }

        return lower.contains("kill '")
            || lower.contains("killing '")
            || lower.contains("kill process ")
            || lower.contains("killing process ")
            || lower.contains("killed process ")
    }

    /// Counts only diagnostic lines that already carry a failure, warning,
    /// timeout, or stall word. Component names in normal startup/configuration
    /// receipts must not become fabricated pipeline failures.
    static func pipelineSignals(in line: String) -> PipelineLogSignals {
        let lower = line.lowercased()
        let warningOrFailure = lower.contains("warn")
            || lower.contains("error")
            || lower.contains("failed")
            || lower.contains("failure")
            || lower.contains("timeout")
            || lower.contains("timed out")
            || lower.contains("stall")
            || lower.contains("fatal")
        guard warningOrFailure else { return PipelineLogSignals() }

        return PipelineLogSignals(
            gfxstreamWarningCount: lower.contains("gfxstream") ? 1 : 0,
            asgStallCount: lower.contains("asg")
                && (lower.contains("stall") || lower.contains("timeout") || lower.contains("failed") || lower.contains("error")) ? 1 : 0,
            vulkanErrorCount: (lower.contains("vulkan") || lower.contains(" vk_"))
                && (lower.contains("error") || lower.contains("failed") || lower.contains("fatal") || lower.contains("timeout")) ? 1 : 0,
            moltenVKWarningCount: (lower.contains("moltenvk") || lower.contains("[mvk]")) ? 1 : 0,
            shaderErrorCount: lower.contains("shader")
                && (lower.contains("error") || lower.contains("failed") || lower.contains("fatal")) ? 1 : 0,
            fenceTimeoutCount: lower.contains("fence")
                && (lower.contains("timeout") || lower.contains("timed out") || lower.contains("stall") || lower.contains("failed")) ? 1 : 0
        )
    }
}
