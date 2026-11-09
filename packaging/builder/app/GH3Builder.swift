// GH3 Builder: builds Guitar Hero III.app on the player's Mac from their
// own PC copy of the game, with the kit in Contents/Resources/kit
// (packaging/builder/make_kit.sh) and the Xcode Command Line Tools. A front
// end for kit/build_game.sh: it reads its @@step/@@progress/@@done lines.

import AppKit
import SwiftUI

@main
struct GH3BuilderApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = BuildModel.shared

  var body: some Scene {
    WindowGroup("GH3 Builder") {
      ContentView().environmentObject(model).frame(width: 600, height: 560)
    }
    .windowResizability(.contentSize)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ note: Notification) { BuildModel.shared.cancel() }
}

final class BuildModel: ObservableObject {
  static let shared = BuildModel()

  enum State: Equatable { case idle, running, done(URL), failed(String) }

  @Published var toolsInstalled = BuildModel.commandLineToolsInstalled()
  @Published var gameDir: URL?
  @Published var outDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Applications")
  @Published var embed = false
  @Published var state = State.idle
  @Published var step = 0
  @Published var stepTotal = 6
  @Published var stepTitle = ""
  @Published var progress: Double?
  @Published var progressText = ""
  @Published var log: [String] = []
  @Published var startedAt = Date()

  private var process: Process?
  private var toolsTimer: Timer?
  private var activity: NSObjectProtocol?
  private var doneApp: URL?

  var kit: URL { Bundle.main.resourceURL!.appendingPathComponent("kit") }

  var gameValid: Bool {
    guard let g = gameDir else { return false }
    return FileManager.default.fileExists(atPath: g.appendingPathComponent("GH3.exe").path)
  }

  // xcode-select -p, not xcrun: on a Mac without the tools, running xcrun
  // or clang pops up Apple's install dialog by itself.
  static func commandLineToolsInstalled() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["-p"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    let dev = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard p.terminationStatus == 0, !dev.isEmpty else { return false }
    return ["usr/bin/clang++", "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"]
      .contains { FileManager.default.isExecutableFile(atPath: dev + "/" + $0) }
  }

  // Apple's installer dialog; checks again every few seconds until done.
  func installTools() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["--install"]
    try? p.run()
    toolsTimer?.invalidate()
    toolsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] t in
      guard let self else { return t.invalidate() }
      if BuildModel.commandLineToolsInstalled() {
        self.toolsInstalled = true
        t.invalidate()
      }
    }
  }

  func chooseFolder(game: Bool) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = !game
    panel.message = game
      ? "Choose your Guitar Hero III folder (the one with GH3.exe)"
      : "Choose where to put Guitar Hero III.app"
    if panel.runModal() == .OK, let url = panel.url {
      if game { gameDir = url } else { outDir = url }
    }
  }

  func start() {
    guard let game = gameDir, state != .running else { return }
    log = []
    step = 0
    stepTitle = "Starting"
    progress = nil
    doneApp = nil
    startedAt = Date()
    state = .running
    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleSystemSleepDisabled], reason: "Building Guitar Hero III")

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [kit.appendingPathComponent("build_game.sh").path, game.path, outDir.path]
      + (embed ? ["--embed-game"] : [])
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    var pending = Data()
    pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      guard !d.isEmpty else { return }
      pending.append(d)
      var lines: [String] = []
      while let nl = pending.firstIndex(of: 0x0A) {
        lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
        pending.removeSubrange(pending.startIndex...nl)
      }
      DispatchQueue.main.async { lines.forEach { self?.handle($0) } }
    }
    p.terminationHandler = { [weak self] p in
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async { self?.finished(status: p.terminationStatus) }
    }
    do {
      try p.run()
      process = p
    } catch {
      finished(status: -1)
    }
  }

  private func handle(_ line: String) {
    if line.hasPrefix("@@step ") {
      let rest = line.dropFirst(7)
      let parts = rest.split(separator: " ", maxSplits: 1)
      let n = parts.first?.split(separator: "/").compactMap { Int($0) } ?? []
      if n.count == 2 { step = n[0]; stepTotal = n[1] }
      stepTitle = parts.count > 1 ? String(parts[1]) : ""
      progress = nil
      progressText = ""
      log.append("== " + stepTitle)
    } else if line.hasPrefix("@@progress ") {
      let n = line.dropFirst(11).split(separator: "/").compactMap { Double($0) }
      if n.count == 2, n[1] > 0 {
        progress = n[0] / n[1]
        progressText = "\(Int(n[0])) of \(Int(n[1])) files"
      }
    } else if line.hasPrefix("@@done ") {
      doneApp = URL(fileURLWithPath: String(line.dropFirst(7)))
    } else {
      log.append(line)
      if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }
  }

  private func finished(status: Int32) {
    if let a = activity { ProcessInfo.processInfo.endActivity(a) }
    activity = nil
    process = nil
    if status == 0, let app = doneApp {
      state = .done(app)
    } else if state == .running {
      let err = log.last { $0.hasPrefix("error:") } ?? log.last ?? "the build stopped"
      state = .failed(status == SIGTERM || status == 15 ? "Cancelled" : err)
    }
  }

  // The script, xargs and every compiler it runs.
  func cancel() {
    guard let p = process, p.isRunning else { return }
    killTree(p.processIdentifier)
  }

  private func killTree(_ pid: pid_t) {
    let q = Process()
    q.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    q.arguments = ["-P", String(pid)]
    let out = Pipe()
    q.standardOutput = out
    try? q.run()
    q.waitUntilExit()
    String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .split(separator: "\n").compactMap { pid_t($0) }.forEach(killTree)
    kill(pid, SIGTERM)
  }
}

struct ContentView: View {
  @EnvironmentObject var m: BuildModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Guitar Hero III for Mac").font(.title2).bold()
        Text("Builds the game on this Mac from your own PC copy of Guitar Hero III: Legends of Rock. The game's files are only read, never changed.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      GroupBox { settings.padding(6) }.disabled(m.state == .running)
      status
      logView
      buttons
    }
    .padding(20)
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(m.toolsInstalled ? "Xcode Command Line Tools installed" : "Needs Apple's Xcode Command Line Tools (free, installed by macOS)",
              systemImage: m.toolsInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .foregroundStyle(m.toolsInstalled ? .green : .orange)
        Spacer()
        if !m.toolsInstalled { Button("Install…") { m.installTools() } }
      }
      row("Game folder", m.gameDir?.path ?? "Not chosen", bad: m.gameDir != nil && !m.gameValid) {
        m.chooseFolder(game: true)
      }
      if m.gameDir != nil && !m.gameValid {
        Text("This folder has no GH3.exe.").font(.caption).foregroundStyle(.red)
      }
      row("Put the app in", m.outDir.path, bad: false) { m.chooseFolder(game: false) }
      Toggle("Copy the game into the app (it then works without the game folder)", isOn: $m.embed)
    }
  }

  private func row(_ title: String, _ value: String, bad: Bool, choose: @escaping () -> Void) -> some View {
    HStack {
      Text(title).frame(width: 100, alignment: .leading)
      Text(value).lineLimit(1).truncationMode(.middle)
        .foregroundStyle(bad ? .red : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Choose…", action: choose)
    }
  }

  @ViewBuilder private var status: some View {
    switch m.state {
    case .idle:
      Text("The first build takes 10–20 minutes, most of it compiling.").foregroundStyle(.secondary)
    case .running:
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Step \(m.step) of \(m.stepTotal): \(m.stepTitle)").bold()
          Spacer()
          TimelineView(.periodic(from: m.startedAt, by: 1)) { ctx in
            Text(elapsed(ctx.date.timeIntervalSince(m.startedAt))).monospacedDigit().foregroundStyle(.secondary)
          }
        }
        if let p = m.progress {
          ProgressView(value: p) { EmptyView() } currentValueLabel: { Text(m.progressText) }
        } else {
          ProgressView().progressViewStyle(.linear)
        }
      }
    case .done(let app):
      Label("Done: \(app.path)", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
    case .failed(let why):
      Label(why, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
    }
  }

  private var logView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        Text(m.log.suffix(400).joined(separator: "\n"))
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(6)
        Color.clear.frame(height: 1).id("end")
      }
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .onChange(of: m.log.count) { _ in proxy.scrollTo("end") }
    }
  }

  private var buttons: some View {
    HStack {
      if case .done(let app) = m.state {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
        Button("Play Guitar Hero III") { NSWorkspace.shared.open(app) }.keyboardShortcut(.defaultAction)
      }
      Spacer()
      if m.state == .running {
        Button("Cancel") { m.cancel() }
      } else {
        Button(m.state == .idle ? "Build" : "Build again") { m.start() }
          .disabled(!m.toolsInstalled || !m.gameValid)
          .keyboardShortcut(m.state == .idle ? .defaultAction : nil)
      }
    }
  }

  private func elapsed(_ s: TimeInterval) -> String {
    String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
  }
}
