import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if args.dropFirst().first == "--preview" {
        let directory = args.dropFirst(2).first ?? "/tmp/shotpanel-preview"
        PreviewDump.run(directory: directory)
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
