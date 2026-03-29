import AppKit
import CommandCenterCore
import SwiftUI
import UniformTypeIdentifiers

private let accentTeal = Color(red: 0.0, green: 0.85, blue: 0.75)
private let accentAmber = Color(red: 1.0, green: 0.75, blue: 0.2)
private let accentGreen = Color(red: 0.2, green: 0.9, blue: 0.5)
private let bgDark = Color(red: 0.06, green: 0.09, blue: 0.12)
private let bgTile = Color(red: 0.08, green: 0.12, blue: 0.16)
private let borderIdle = Color.white.opacity(0.08)
private let textDim = Color.white.opacity(0.35)
private let textMid = Color.white.opacity(0.6)

@main
struct CommandCenterApp: App {
    @StateObject private var viewModel = POCViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Cursor Commander", id: "poc") {
            POCContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    Telemetry.sendDailyPingIfNeeded(
                        version: version,
                        activeTiles: viewModel.tiles.count,
                        agentTurnsToday: 0
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        FloatingWindowController.makeKeyWindowFloat()
                    }
                }
                .onDisappear { viewModel.stop() }
        }
        .defaultSize(width: 640, height: 320)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let wasSetUp = FirstLaunchSetup.isFullySetUp
        if !wasSetUp {
            let result = FirstLaunchSetup.performSetup()
            if !result.success {
                NSLog("[CommandCenter] Setup issues: \(result.errors.joined(separator: "; "))")
            }
            if result.success {
                Telemetry.sendInstallPing(version: appVersion)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            FloatingWindowController.makeKeyWindowFloat()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

enum FloatingWindowController {
    private static func commanderWindow() -> NSWindow? {
        NSApplication.shared.windows.first(where: { $0.title.contains("Commander") || $0.title.contains("Command Center") })
    }

    static func makeKeyWindowFloat() {
        guard let window = commanderWindow() else { return }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    static func temporarilyLower() {
        guard let window = commanderWindow() else { return }
        window.level = .normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let w = commanderWindow() else { return }
            w.level = .floating
        }
    }
}

enum CursorWindowActivator {
    static func activate(tile: AgentTile) {
        FloatingWindowController.temporarilyLower()

        let path = tile.workspacePath
        if !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: "/Applications/Cursor.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.todesktop.230313mzl4w4u92" }
            apps.first?.activate()
        }

        let leafName = tile.leafName
        guard !leafName.isEmpty, AXIsProcessTrusted() else { return }
        let script = """
        tell application "System Events"
            tell process "Cursor"
                set frontmost to true
                repeat with w in windows
                    if name of w contains "\(leafName)" then
                        perform action "AXRaise" of w
                        exit repeat
                    end if
                end repeat
            end tell
        end tell
        """
        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }
}

private struct POCContentView: View {
    @EnvironmentObject private var viewModel: POCViewModel
    @State private var showSettings = false
    @State private var showUninstallConfirm = false
    @State private var draggingTileId: String?
    @State private var updateInstallError: String?

    private var thinkingCount: Int {
        viewModel.tiles.filter { $0.agentState == .thinking }.count
    }
    private var waitingCount: Int {
        viewModel.tiles.filter { $0.agentState == .waitingForInput }.count
    }
    private var doneCount: Int {
        viewModel.tiles.filter { $0.agentState == .recentlyCompleted }.count
    }
    private var idleCount: Int {
        viewModel.tiles.filter { $0.agentState == .idle }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let offer = viewModel.updateOffer {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accentTeal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white)
                        Text("v\(offer.version) is published on GitHub.")
                            .font(.caption2)
                            .foregroundStyle(textDim)
                    }
                    Spacer(minLength: 8)
                    if viewModel.isDownloadingUpdate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Install") {
                            Task { @MainActor in
                                do {
                                    let zip = try await viewModel.downloadUpdateArtifact()
                                    try UpdateInstaller.spawnInstallAfterQuit(zipPath: zip)
                                    NSApplication.shared.terminate(nil)
                                } catch {
                                    updateInstallError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentTeal)
                        .controlSize(.small)
                        Button("Later") {
                            viewModel.dismissUpdateBanner()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(textMid)
                        .font(.caption)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(bgTile)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accentTeal.opacity(0.45), lineWidth: 1)
                        )
                )
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURSOR COMMANDER")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(.white)
                    if !viewModel.tiles.isEmpty {
                        summaryLine
                    }
                }
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(textMid)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    settingsPopover
                }
            }
            .padding(.bottom, 4)

            if viewModel.tiles.isEmpty {
                RadarEmptyState()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(viewModel.tiles) { tile in
                            TileView(
                                tile: tile,
                                onAcknowledgeDone: {
                                    viewModel.acknowledgeDone(forAgentId: tile.id)
                                },
                                onActivate: {
                                    if tile.agentState == .recentlyCompleted || tile.agentState == .waitingForInput {
                                        viewModel.acknowledgeDone(forAgentId: tile.id)
                                    }
                                    CursorWindowActivator.activate(tile: tile)
                                },
                                onDismiss: { permanent in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        viewModel.dismiss(agentId: tile.id, permanent: permanent)
                                    }
                                },
                                onRename: { newName in
                                    viewModel.setDisplayName(newName, forAgentId: tile.id)
                                }
                            )
                            .opacity(draggingTileId == tile.id ? 0.4 : 1.0)
                            .onDrag {
                                draggingTileId = tile.id
                                return NSItemProvider(object: tile.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: TileDropDelegate(
                                tileId: tile.id,
                                draggingTileId: $draggingTileId,
                                viewModel: viewModel
                            ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(bgDark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshNow()
            Task { await viewModel.refreshUpdateOffer() }
        }
        .alert("Update install failed", isPresented: Binding(
            get: { updateInstallError != nil },
            set: { if !$0 { updateInstallError = nil } }
        )) {
            Button("OK", role: .cancel) { updateInstallError = nil }
        } message: {
            Text(updateInstallError ?? "")
        }
    }

    private var summaryLine: some View {
        HStack(spacing: 0) {
            if thinkingCount > 0 {
                Text("\(thinkingCount) thinking")
                    .foregroundStyle(accentTeal)
                separator
            }
            if waitingCount > 0 {
                Text("\(waitingCount) waiting")
                    .foregroundStyle(accentAmber)
                separator
            }
            if doneCount > 0 {
                Text("\(doneCount) done")
                    .foregroundStyle(accentGreen)
                separator
            }
            Text("\(idleCount) idle")
                .foregroundStyle(textDim)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var separator: some View {
        Text("  \u{00B7}  ")
            .foregroundStyle(textDim)
            .font(.system(.caption, design: .monospaced))
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.statusLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Divider()
            Button("Check for updates") {
                Task { await viewModel.refreshUpdateOffer() }
            }
            .font(.caption)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button("Reinstall Cursor Rule") {
                    FirstLaunchSetup.performSetup()
                }
                .font(.caption)
                Button("Uninstall Command Center...") {
                    showUninstallConfirm = true
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 340)
        .alert("Uninstall Command Center?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                Telemetry.sendUninstallPing(version: version)
                FirstLaunchSetup.performUninstall()
                let appPath = "/Applications/Command Center.app"
                try? FileManager.default.removeItem(atPath: appPath)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } message: {
            Text("This will remove the app, the Cursor agent rule, and all signal data. Your Cursor projects are not affected.")
        }
    }
}

private struct TileDropDelegate: DropDelegate {
    let tileId: String
    @Binding var draggingTileId: String?
    let viewModel: POCViewModel

    func dropEntered(info: DropInfo) {
        guard let from = draggingTileId, from != tileId else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.moveTile(fromId: from, toId: tileId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTileId = nil
        return true
    }

    func dropExited(info: DropInfo) {}

    func validateDrop(info: DropInfo) -> Bool { true }
}

private struct TileView: View {
    let tile: AgentTile
    let onAcknowledgeDone: () -> Void
    let onActivate: () -> Void
    /// `permanent == true` means never show this signal file again until registry reset.
    let onDismiss: (_ permanent: Bool) -> Void
    let onRename: (String) -> Void
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovering = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("Tile name", text: $editText, onCommit: commitEdit)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onExitCommand { cancelEdit() }
            } else {
                Text(tile.displayName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(tile.agentState == .idle ? textMid : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        editText = tile.displayName
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            fieldFocused = true
                        }
                    }
            }

            Text(tile.workspacePath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(textDim)
                .lineLimit(1)
                .truncationMode(.head)
                .help(tile.workspacePath)

            Spacer(minLength: 4)

            statusRow
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(12)
        .background(bgTile)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tileBorderColor, lineWidth: tileBorderWidth)
        )
        .shadow(color: tileShadowColor, radius: tileShadowRadius, x: 0, y: 0)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Menu {
                    Button("Hide until next activity") {
                        onDismiss(false)
                    }
                    Button("Hide permanently") {
                        onDismiss(true)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Hide tile: snooze until next cc-signal turn, or ignore this signal file")
                .transition(.opacity)
                // Tight to the card’s top-trailing corner (inside the padded content area).
                .padding(.top, 2)
                .padding(.trailing, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onActivate()
        }
    }

    private func commitEdit() {
        onRename(editText)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }

    @ViewBuilder
    private var statusRow: some View {
        switch tile.agentState {
        case .thinking:
            HStack(spacing: 6) {
                ThinkingDots()
                Text("THINKING")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentTeal)
            }
        case .waitingForInput:
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accentAmber)
                Text("WAITING")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentAmber)
            }
        case .recentlyCompleted:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accentGreen)
                Text("DONE")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(accentGreen)
            }
        case .idle:
            Text("IDLE")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(textDim)
        }
    }

    private var tileBorderColor: Color {
        switch tile.agentState {
        case .thinking: return accentTeal.opacity(0.5)
        case .waitingForInput: return accentAmber.opacity(0.5)
        case .recentlyCompleted: return accentGreen.opacity(0.4)
        case .idle: return borderIdle
        }
    }

    private var tileBorderWidth: CGFloat {
        tile.agentState == .idle ? 1 : 1.5
    }

    private var tileShadowColor: Color {
        switch tile.agentState {
        case .thinking: return accentTeal.opacity(0.2)
        case .waitingForInput: return accentAmber.opacity(0.2)
        case .recentlyCompleted: return accentGreen.opacity(0.15)
        case .idle: return .clear
        }
    }

    private var tileShadowRadius: CGFloat {
        tile.agentState == .idle ? 0 : 8
    }
}

private struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(accentTeal)
                    .frame(width: 4, height: 4)
                    .opacity(i <= phase ? 1.0 : 0.25)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 4
        }
    }
}

// MARK: - Radar empty state

private let radarTeal = NSColor(red: 42 / 255, green: 157 / 255, blue: 143 / 255, alpha: 1)

private struct RadarEmptyState: View {
    @State private var cursorVisible = true
    private let cursorTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RadarGridBackground()
            RadarScanLine()

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                RadarCanvasView()
                    .frame(width: 180, height: 180)
                    .padding(.bottom, 20)

                HStack(spacing: 6) {
                    Text("SCANNING FOR AGENTS")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 42 / 255, green: 128 / 255, blue: 112 / 255))
                        .tracking(1.2)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accentTeal.opacity(0.7))
                        .frame(width: 7, height: 14)
                        .shadow(color: accentTeal.opacity(0.5), radius: 4)
                        .opacity(cursorVisible ? 1 : 0)
                }
                .padding(.bottom, 6)

                VStack(spacing: 2) {
                    Text("Open a Cursor window and start a conversation.")
                    Text("It will appear here automatically.")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(red: 42 / 255, green: 90 / 255, blue: 90 / 255).opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

                VStack(spacing: 7) {
                    RadarStep(number: "1", text: "Open any project in **Cursor**")
                    RadarStep(number: "2", text: "Start **any chat** with an agent")
                    RadarStep(number: "3", text: "Watch it appear on your **dashboard**")
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(cursorTimer) { _ in
            cursorVisible.toggle()
        }
    }
}

private struct RadarStep: View {
    let number: String
    let text: AttributedString

    init(number: String, text: String) {
        self.number = number
        var attr = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        attr.foregroundColor = Color(red: 42 / 255, green: 100 / 255, blue: 100 / 255).opacity(0.85)
        attr.font = .system(size: 10, design: .monospaced)
        self.text = attr
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.55))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.07))
                        .overlay(Circle().stroke(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.22), lineWidth: 0.5))
                )
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.1), lineWidth: 0.5))
        )
    }
}

private struct RadarGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let teal = radarTeal.withAlphaComponent(0.04).cgColor
            for x in stride(from: 0, through: size.width, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color(cgColor: teal)), lineWidth: 1)
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Color(cgColor: teal)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RadarScanLine: View {
    @State private var offset: CGFloat = 0.1
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(red: 42 / 255, green: 157 / 255, blue: 143 / 255).opacity(0.15), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .offset(y: geo.size.height * offset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                        offset = 0.9
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

private struct BlipState {
    var ax: Double
    var ay: Double
    var age: Int = 0
    let maxAge: Int = 180
}

private struct RadarCanvasView: View {
    @State private var angle: Double = 0
    @State private var blips: [BlipState] = [
        BlipState(ax: 0.38, ay: 0.28),
        BlipState(ax: 0.18, ay: 0.62),
        BlipState(ax: 0.72, ay: 0.70),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let radius = min(cx, cy) - 2

                drawRadarDisk(context: context, cx: cx, cy: cy, r: radius)
                drawConcentricCircles(context: context, cx: cx, cy: cy, r: radius)
                drawRadialLines(context: context, cx: cx, cy: cy, r: radius)
                drawSweep(context: context, cx: cx, cy: cy, r: radius, angle: angle)
                drawBlips(context: context, cx: cx, cy: cy, r: radius, angle: angle)
                drawOuterRing(context: context, cx: cx, cy: cy, r: radius)
                drawTickMarks(context: context, cx: cx, cy: cy, r: radius)
                drawCenter(context: context, cx: cx, cy: cy)
            }
            .onChange(of: timeline.date) { _, _ in
                angle += 0.018
                for i in blips.indices {
                    let bx = cx(blips[i].ax, radius: 88)
                    let by = cy(blips[i].ay, radius: 88)
                    let d = sweepDelta(angle, bx: bx, by: by, cx: 90, cy: 90)
                    if d < 0.06 { blips[i].age = blips[i].maxAge }
                    if blips[i].age > 0 { blips[i].age -= 1 }
                }
            }
        }
    }

    private func cx(_ ax: Double, radius: Double) -> Double { 90 + (ax - 0.5) * 2 * radius * 0.88 }
    private func cy(_ ay: Double, radius: Double) -> Double { 90 + (ay - 0.5) * 2 * radius * 0.88 }

    private func sweepDelta(_ angle: Double, bx: Double, by: Double, cx: Double, cy: Double) -> Double {
        let da = atan2(by - cy, bx - cx)
        return (angle - da + .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
    }

    private func drawRadarDisk(context: GraphicsContext, cx: Double, cy: Double, r: Double) {
        let disk = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        context.fill(disk, with: .color(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255)))
    }

    private func drawConcentricCircles(context: GraphicsContext, cx: Double, cy: Double, r: Double) {
        for factor in [0.25, 0.5, 0.75, 1.0] {
            let cr = r * factor
            var path = Path()
            path.addEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
            context.stroke(path, with: .color(Color(nsColor: radarTeal.withAlphaComponent(0.18))), lineWidth: 0.8)
        }
    }

    private func drawRadialLines(context: GraphicsContext, cx: Double, cy: Double, r: Double) {
        for i in 0..<12 {
            let a = Double(i) / 12.0 * .pi * 2
            var path = Path()
            path.move(to: CGPoint(x: cx, y: cy))
            path.addLine(to: CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r))
            context.stroke(path, with: .color(Color(nsColor: radarTeal.withAlphaComponent(0.12))), lineWidth: 0.7)
        }
    }

    private func drawSweep(context: GraphicsContext, cx: Double, cy: Double, r: Double, angle: Double) {
        var clipped = context
        clipped.clipToLayer { ctx in
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(.white))
        }

        let trailLen = Double.pi * 0.55
        let steps = 40
        for i in 0..<steps {
            let t = Double(i) / Double(steps)
            let a0 = angle - trailLen * (1 - t)
            let a1 = angle - trailLen * (1 - Double(i + 1) / Double(steps))
            var path = Path()
            path.move(to: CGPoint(x: cx, y: cy))
            path.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            path.closeSubpath()
            clipped.fill(path, with: .color(Color(nsColor: radarTeal.withAlphaComponent(t * 0.22))))
        }

        var armPath = Path()
        armPath.move(to: CGPoint(x: cx, y: cy))
        armPath.addLine(to: CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r))
        clipped.stroke(
            armPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(nsColor: radarTeal.withAlphaComponent(0.0)), location: 0),
                    .init(color: Color(nsColor: radarTeal.withAlphaComponent(0.6)), location: 0.5),
                    .init(color: Color(nsColor: radarTeal.withAlphaComponent(1.0)), location: 1),
                ]),
                startPoint: CGPoint(x: cx, y: cy),
                endPoint: CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            ),
            lineWidth: 1.5
        )
    }

    private func drawBlips(context: GraphicsContext, cx: Double, cy: Double, r: Double, angle: Double) {
        for blip in blips {
            guard blip.age > 0 else { continue }
            let bx = cx + (blip.ax - 0.5) * 2 * r * 0.88
            let by = cy + (blip.ay - 0.5) * 2 * r * 0.88
            let life = Double(blip.age) / Double(blip.maxAge)
            let dotR = 3 + life * 4

            let glowR = dotR * 3.5
            context.fill(
                Path(ellipseIn: CGRect(x: bx - glowR, y: by - glowR, width: glowR * 2, height: glowR * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 42 / 255, green: 220 / 255, blue: 200 / 255).opacity(life * 0.7), location: 0),
                        .init(color: Color(red: 42 / 255, green: 180 / 255, blue: 160 / 255).opacity(life * 0.3), location: 0.4),
                        .init(color: Color(nsColor: radarTeal.withAlphaComponent(0)), location: 1),
                    ]),
                    center: CGPoint(x: bx, y: by),
                    startRadius: 0,
                    endRadius: glowR
                )
            )

            let tailLen = life * 22
            let tailAngle = angle - 0.08
            var tailPath = Path()
            tailPath.move(to: CGPoint(x: bx, y: by))
            tailPath.addLine(to: CGPoint(x: bx - cos(tailAngle) * tailLen, y: by - sin(tailAngle) * tailLen))
            context.stroke(
                tailPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 100 / 255, green: 1, blue: 230 / 255).opacity(life * 0.8),
                        Color(nsColor: radarTeal.withAlphaComponent(0)),
                    ]),
                    startPoint: CGPoint(x: bx, y: by),
                    endPoint: CGPoint(x: bx - cos(tailAngle) * tailLen, y: by - sin(tailAngle) * tailLen)
                ),
                lineWidth: life * 2.5
            )

            let coreR = dotR * 0.6
            context.fill(
                Path(ellipseIn: CGRect(x: bx - coreR, y: by - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(Color(red: 180 / 255, green: 1, blue: 240 / 255).opacity(min(1, life * 1.2)))
            )
        }
    }

    private func drawOuterRing(context: GraphicsContext, cx: Double, cy: Double, r: Double) {
        var outer = Path()
        outer.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        context.stroke(outer, with: .color(Color(nsColor: radarTeal.withAlphaComponent(0.45))), lineWidth: 1.5)
        let ir = r - 4
        var inner = Path()
        inner.addEllipse(in: CGRect(x: cx - ir, y: cy - ir, width: ir * 2, height: ir * 2))
        context.stroke(inner, with: .color(Color(nsColor: radarTeal.withAlphaComponent(0.1))), lineWidth: 0.8)
    }

    private func drawTickMarks(context: GraphicsContext, cx: Double, cy: Double, r: Double) {
        for i in 0..<72 {
            let a = Double(i) / 72.0 * .pi * 2
            let major = i % 6 == 0
            let r0 = major ? r - 10 : r - 6
            var path = Path()
            path.move(to: CGPoint(x: cx + cos(a) * r0, y: cy + sin(a) * r0))
            path.addLine(to: CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r))
            context.stroke(
                path,
                with: .color(Color(nsColor: radarTeal.withAlphaComponent(major ? 0.5 : 0.2))),
                lineWidth: major ? 1 : 0.6
            )
        }
    }

    private func drawCenter(context: GraphicsContext, cx: Double, cy: Double) {
        context.fill(
            Path(ellipseIn: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 120 / 255, green: 1, blue: 230 / 255), location: 0),
                    .init(color: Color(red: 42 / 255, green: 200 / 255, blue: 180 / 255).opacity(0.8), location: 0.4),
                    .init(color: Color(nsColor: radarTeal.withAlphaComponent(0)), location: 1),
                ]),
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: 8
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5)),
            with: .color(Color(red: 238 / 255, green: 1, blue: 248 / 255))
        )
    }
}
