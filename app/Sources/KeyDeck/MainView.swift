import SwiftUI
import AppKit
import KeyDeckCore
import KeyDeckEngine

/// The whole app in one window, in the order a new user needs it:
/// turn it on → choose how to enter Nav Mode → give your apps keys.
///
/// Every change takes effect the instant it is made; there is no Apply button
/// and no way to be "saved but not running".
struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showLicense = false
    @State private var showCheatSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.needsPermission {
                        PermissionCard(model: model)
                    } else {
                        TriggerCard(model: model)
                        DisplaysCard(model: model)
                        LauncherList(model: model, showLicense: $showLicense)
                    }
                    if let err = model.saveError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 460)
        .frame(minHeight: 520)
        .task { await model.license.revalidateIfStale() }
        .sheet(isPresented: $showLicense) { LicenseSheet(license: model.license) }
        // ⌘S flushes a pending save immediately.
        .background(
            Button("") { model.persistNow() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            StatusDot(state: model.engineState)
            Text(model.statusLine)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Cheat sheet") { showCheatSheet = true }
                .buttonStyle(.borderless).font(.caption)
                .popover(isPresented: $showCheatSheet, arrowEdge: .top) {
                    CheatSheetPreview(sections: model.cheatSheet)
                }
            Toggle("Open at login", isOn: $model.launchAtLogin)
                .toggleStyle(.checkbox).font(.caption)
            Button(model.license.statusText()) { showLicense = true }
                .buttonStyle(.borderless).foregroundStyle(.secondary).font(.caption)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

// MARK: - Permission

/// The only thing standing between a fresh download and a working product.
/// Shown alone, with one button, because nothing else on this screen matters
/// until it is done.
private struct PermissionCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One click to turn KeyDeck on")
                .font(.title3.weight(.semibold))
            Text("""
                 macOS asks every keyboard tool for Accessibility permission. It is \
                 the only permission KeyDeck needs, and nothing else gets installed. \
                 Click below, tick KeyDeck in the list that opens, and this window \
                 switches itself on.
                 """)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on KeyDeck") { model.requestPermission() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if case .failed(let msg) = model.engineState {
                Text(msg).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Trigger

/// How Nav Mode is entered. The two options are deliberately different in kind:
/// a normal shortcut for people who have one to spare, and a bare modifier tap
/// for people who don't — which is the whole reason this product exists.
private struct TriggerCard: View {
    @ObservedObject var model: AppModel

    private var activator: Binding<NavActivator> {
        Binding(get: { model.config.features.nav.activator },
                set: { model.config.features.nav.activator = $0 })
    }

    private var usesTap: Bool {
        let kind = model.config.features.nav.activator.kind
        return kind == "tapModifier" || kind == "doubleTapModifier"
    }

    var body: some View {
        Card(title: "Nav Mode", isOn: $model.config.features.nav.enabled) {
            Picker("", selection: Binding(
                get: { usesTap ? "tap" : "hotkey" },
                set: { activator.wrappedValue.kind = ($0 == "tap") ? "tapModifier" : "hotkey" })) {
                Text("Keyboard shortcut").tag("hotkey")
                Text("Tap a modifier").tag("tap")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if usesTap {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(
                        get: { activator.wrappedValue.modifier },
                        set: { activator.wrappedValue.modifier = $0 })) {
                        Text("Right ⌥").tag("rightAlt")
                        Text("Right ⌘").tag("rightCmd")
                        Text("Right ⌃").tag("rightCtrl")
                        Text("Left ⌥").tag("leftAlt")
                    }
                    .labelsHidden().frame(width: 110)

                    Toggle("Tap twice", isOn: Binding(
                        get: { activator.wrappedValue.kind == "doubleTapModifier" },
                        set: { activator.wrappedValue.kind = $0 ? "doubleTapModifier" : "tapModifier" }))
                    Spacer()
                }
                Text("Costs you no shortcut at all — the modifier still works normally in combinations.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    Text("Enter with").foregroundStyle(.secondary)
                    ShortcutRecorder(binding: Binding(
                        get: { activator.wrappedValue.hotkey },
                        set: { activator.wrappedValue.hotkey = $0 }))
                        .frame(width: 130, height: 26)
                    Spacer()
                }
            }

            Text("Press it again or Esc to leave. Inside: h j k l move, d u scroll, space clicks, ? shows everything.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Displays

private struct DisplaysCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card(title: "Displays", isOn: $model.config.features.monitors.enabled) {
            HStack(spacing: 8) {
                Toggle("Jump to the next display when you tap",
                       isOn: $model.config.features.monitors.optionTapCycle)
                Picker("", selection: $model.config.features.monitors.cycleModifier) {
                    Text("⌥ Option").tag("alt")
                    Text("⌃ Control").tag("ctrl")
                    Text("⌘ Command").tag("cmd")
                }
                .labelsHidden().frame(width: 118)
                .disabled(!model.config.features.monitors.optionTapCycle)
                Spacer()
            }
            Text("Only a clean tap counts — using the modifier in a shortcut never moves the pointer. Inside Nav Mode, 1 2 3 jump straight to a display.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared pieces

/// A titled card with an enable toggle; its content shows only when enabled.
struct Card<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) { Text(title).font(.headline) }.toggleStyle(.switch)
            if isOn {
                VStack(alignment: .leading, spacing: 8) { content() }.padding(.leading, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: .separatorColor).opacity(0.5)))
    }
}

private struct StatusDot: View {
    let state: EngineState
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        switch state {
        case .running: return .green
        case .needsPermission: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }
}

/// The `?` overlay's contents, rendered in the settings window so users can read
/// the bindings without entering the mode first.
private struct CheatSheetPreview: View {
    let sections: [HUDSection]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ForEach(section.items) { item in
                        HStack(spacing: 10) {
                            Text(item.keys)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 66, alignment: .leading)
                            Text(item.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}
