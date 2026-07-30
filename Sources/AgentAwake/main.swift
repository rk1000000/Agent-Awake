import AppKit

if CommandLine.arguments.contains("--diagnostics") {
    exit(Diagnostics.run())
}

let application = NSApplication.shared
let delegate = AppController()
application.delegate = delegate
application.run()
