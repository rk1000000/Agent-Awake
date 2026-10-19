import Foundation

// Build two read-only probes from the helper's real polling code. Neither probe
// calls power setters, writes heartbeat/ownership files, or requires root.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let source = try String(contentsOf: root.appendingPathComponent("Sources/AgentAwakePowerHelper/main.swift"), encoding: .utf8)
guard let signalStart = source.range(of: "signal(SIGTERM)"),
      let loopStart = source.range(of: "while !shouldStop {\n"),
      let loopEnd = source.range(of: "\n}\n\nif owns", range: loopStart.upperBound..<source.endIndex) else {
    fatalError("Cannot locate helper polling loop")
}
let prefix = String(source[..<signalStart.lowerBound])
let fixedBody = String(source[loopStart.upperBound..<loopEnd.lowerBound])
    .replacingOccurrences(of: "reconcile()", with: "readOnlyIteration()")
    .replacingOccurrences(of: "Thread.sleep(forTimeInterval: 1)", with: "")
guard fixedBody.contains("autoreleasepool") else { fatalError("Polling loop lacks autoreleasepool") }
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("agentawake-memory-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

func execute(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Probe command failed: \(arguments.first ?? "")") }
    return String(decoding: data, as: UTF8.self)
}

let binPath = try execute(["swift", "build", "-c", "release", "--show-bin-path", "--package-path", root.path])
    .trimmingCharacters(in: .whitespacesAndNewlines)
let objects = try FileManager.default.contentsOfDirectory(atPath: "\(binPath)/AgentAwakeCore.build")
    .filter { $0.hasSuffix(".swift.o") }.map { "\(binPath)/AgentAwakeCore.build/\($0)" }
guard !objects.isEmpty else { fatalError("Build AgentAwakePowerHelper first") }

func probe(name: String, body: String) throws -> [Int64] {
    let suffix = """
    private func readOnlyIteration() {
        _ = validHeartbeat()
        _ = sleepIsDisabled()
        _ = ClamshellController.lidIsClosed()
        _ = owns(lowPowerOwnershipMarker)
    }
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return info.phys_footprint
    }
    private func batch(_ iterations: Int) {
        for _ in 0..<iterations {
    \(body)
        }
    }
    batch(100)
    let start = footprint()
    batch(2000)
    let middle = footprint()
    batch(2000)
    print("\\(start) \\(middle) \\(footprint())")
    """
    let swiftFile = temporary.appendingPathComponent("main.swift")
    try (prefix + suffix).write(to: swiftFile, atomically: true, encoding: .utf8)
    let executable = temporary.appendingPathComponent(name)
    _ = try execute(["swiftc", "-O", "-I", "\(binPath)/Modules", "-framework", "IOKit", swiftFile.path] + objects + ["-o", executable.path])
    let result = try execute([executable.path]).split(whereSeparator: \.isWhitespace).compactMap { Int64($0) }
    guard result.count == 3 else { fatalError("Invalid footprint measurements") }
    print("\(name): bytes=\(result), second_batch_growth=\(result[2] - result[1])")
    return result
}

let baseline = try probe(name: "without-pool", body: "readOnlyIteration()")
let fixed = try probe(name: "with-pool", body: fixedBody)
let baselineGrowth = baseline[2] - baseline[1]
let fixedGrowth = fixed[2] - fixed[1]
guard baselineGrowth >= 16 * 1024 * 1024,
      fixedGrowth <= 8 * 1024 * 1024 else {
    fatalError("Memory regression check failed or baseline did not reproduce")
}
print("PASS: baseline reproduces accumulation; fixed polling releases temporary objects")
print("Probe artifacts: \(temporary.path)")
