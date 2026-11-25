import AppKit
import SwiftUI

// MenuBarExtra may retain its SwiftUI content after the user closes the panel.
private struct PanelWindowReader: NSViewRepresentable {
    let changed: (Bool, CGFloat) -> Void

    final class Reader: NSView {
        var changed: ((Bool, CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for event in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification,
                              NSApplication.didChangeScreenParametersNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(update),
                        name: event, object: event == NSApplication.didChangeScreenParametersNotification ? nil : window)
                }
            }
            update()
        }

        @objc private func update() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let screen = window?.screen ?? NSScreen.main
                changed?(window?.occlusionState.contains(.visible) == true, screen?.visibleFrame.height ?? 700)
            }
        }
    }

    func makeNSView(context: Context) -> Reader {
        let reader = Reader()
        reader.changed = changed
        return reader
    }

    func updateNSView(_ nsView: Reader, context: Context) { nsView.changed = changed }
}

private struct ControlPanel: View {
    @ObservedObject var controller: AppController
    @State private var expanded = false
    @State private var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 700

    private var installed: [LiteProduct] { LiteProduct.all.filter { controller.locations[$0.id] != nil } }
    private var missing: [LiteProduct] { LiteProduct.publicProducts.filter { controller.locations[$0.id] == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LiteControl").font(.headline)
                Spacer()
                HStack {
                    Button(String(localized: "Start All")) { controller.setAll(to: true) }
                    Text("·").foregroundStyle(.tertiary)
                    Button(String(localized: "Quit All")) { controller.setAll(to: false) }
                }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .disabled(!installed.contains(where: controller.canControl))
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 11)

            Divider()
            let visibleRows = installed.count + (expanded ? missing.count : 0)
            let rowsHeight = CGFloat(visibleRows) * Self.rowHeight + (missing.isEmpty ? 0 : Self.discoveryHeight)
            let availableHeight = max(Self.rowHeight, screenHeight - 164)
            if rowsHeight > availableHeight {
                ScrollView { productList }
                    .frame(height: availableHeight)
            } else {
                productList
            }

            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).help(message)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            Divider()

            HStack {
                Toggle(String(localized: "Open at Login"), isOn: Binding(
                    get: { controller.launchAtLogin }, set: controller.setLaunchAtLogin
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button(String(localized: "Quit LiteControl")) { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }
            .font(.system(size: 12)).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(PanelWindowReader { visible, height in
            if screenHeight != height { screenHeight = height }
            controller.setPanelVisible(visible)
        })
        .onDisappear { controller.setPanelVisible(false) }
    }

    private static let rowHeight: CGFloat = 41
    private static let discoveryHeight: CGFloat = 33

    private var productList: some View {
        VStack(spacing: 0) {
            ForEach(installed) { product in installedRow(product) }
            if !missing.isEmpty {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .frame(width: 10).font(.caption)
                        Text(String(localized: "Discover More Lite Apps"))
                        Spacer()
                        Text("\(missing.count)").monospacedDigit()
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: Self.discoveryHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
                if expanded {
                    ForEach(missing) { product in
                        HStack(spacing: 11) {
                            identity(product)
                            if let repository = product.repository {
                                Link(destination: repository.appendingPathComponent("releases")) {
                                    Label(String(localized: "Download"), systemImage: "arrow.down.circle")
                                }
                                .font(.system(size: 12))
                                .help(String(localized: "Download \(product.name) from GitHub Releases"))
                                .accessibilityLabel(String(localized: "Download \(product.name)"))
                            }
                        }
                        .frame(height: Self.rowHeight)
                        .contextMenu { locateButton(product) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func identity(_ product: LiteProduct) -> some View {
        let label = HStack(spacing: 11) {
            Image(nsImage: product.icon(at: controller.locations[product.id]))
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 25, height: 25).accessibilityHidden(true)
            Text(product.name).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())

        if let repository = product.repository {
            Link(destination: repository) { label }
                .buttonStyle(.plain)
                .help(String(localized: "Open the GitHub repository for \(product.name)"))
                .accessibilityLabel(String(localized: "Open the GitHub repository for \(product.name)"))
        } else {
            label
        }
    }

    @ViewBuilder private func locateButton(_ product: LiteProduct) -> some View {
        if case .application = product.control {
            Button(String(localized: "Choose \(product.name).app…")) { controller.chooseApplication(product) }
        }
    }

    private func installedRow(_ product: LiteProduct) -> some View {
        HStack(spacing: 11) {
            identity(product)
            if case .postWindow = product.control, controller.postVisible == nil {
                Text(controller.postHost == nil ? String(localized: "Start Hammerspoon") : String(localized: "Disconnected"))
                    .font(.caption).foregroundStyle(.secondary)
                    .help(String(localized: "Start Hammerspoon and load LitePost and hs.ipc."))
            } else if case .application = product.control {
                Button { controller.chooseApplication(product) } label: {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help(String(localized: "Choose \(product.name).app"))
                .accessibilityLabel(String(localized: "Locate \(product.name)"))
            }
            Toggle(product.name, isOn: Binding(
                get: { controller.isRunning(product) },
                set: { controller.setRunning(product, to: $0) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .disabled(!controller.canControl(product))
        }
        .frame(height: Self.rowHeight)
    }
}

@main
private struct LiteControlApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("LiteControl", systemImage: "slider.horizontal.3") {
            ControlPanel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
