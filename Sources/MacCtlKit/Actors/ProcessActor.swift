@preconcurrency import AppKit
import Foundation
import Darwin

public struct ProcessRecord: Sendable {
    public let pid: pid_t
    public let name: String
    public let status: String    // "running", "sleeping", "zombie", "stopped"
    public let memoryMB: Double
    public let cpuPercent: Double
    public let parentPID: pid_t
    public let isApp: Bool
}

public actor ProcessActor {
    public init() {}

    public func list(filter: String? = nil) -> [ProcessRecord] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        sysctl(&mib, 4, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 4, &procs, &size, nil, 0)

        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })

        return procs.prefix(count).compactMap { p -> ProcessRecord? in
            let pid = p.kp_proc.p_pid
            guard pid > 0 else { return nil }
            let name = withUnsafeBytes(of: p.kp_proc.p_comm) { bytes in
                String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            }
            guard !name.isEmpty else { return nil }
            if let f = filter, !name.localizedCaseInsensitiveContains(f) { return nil }

            // p_stat is CChar (Int8) — compare as Int8
            let stat = p.kp_proc.p_stat
            let status: String
            if stat == Int8(SRUN)   { status = "running"  }
            else if stat == Int8(SSLEEP) { status = "sleeping" }
            else if stat == Int8(SZOMB)  { status = "zombie"   }
            else if stat == Int8(SSTOP)  { status = "stopped"  }
            else { status = "other" }

            return ProcessRecord(
                pid: pid, name: name, status: status,
                memoryMB: memoryUsage(pid: pid),
                cpuPercent: 0,
                parentPID: p.kp_eproc.e_ppid,
                isApp: runningPIDs.contains(pid))
        }.sorted { $0.memoryMB > $1.memoryMB }
    }

    public func kill(pid: pid_t, force: Bool = false) throws {
        let sig: Int32 = force ? SIGKILL : SIGTERM
        if Darwin.kill(pid, sig) != 0 { throw ProcessError.killFailed(pid, errno) }
    }

    public func kill(name: String, force: Bool = false) throws {
        let matches = list(filter: name).filter { $0.name == name }
        guard !matches.isEmpty else { throw ProcessError.notFound(name) }
        for p in matches { try kill(pid: p.pid, force: force) }
    }

    public func get(pid: pid_t) -> ProcessRecord? { list().first { $0.pid == pid } }
    public func isRunning(name: String) -> Bool {
        !list(filter: name).filter { $0.name == name }.isEmpty
    }

    private func memoryUsage(pid: pid_t) -> Double {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return 0 }
        return Double(info.pti_resident_size) / 1_048_576
    }
}

public enum ProcessError: Error, Sendable {
    case killFailed(pid_t, Int32)
    case notFound(String)
}
