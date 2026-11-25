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
                    Button("全部开启") { controller.setAll(to: true) }
                    Text("·").foregroundStyle(.tertiary)
                    Button("全部关闭") { controller.setAll(to: false) }
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
                Toggle("开机启动 LiteControl", isOn: Binding(
                    get: { controller.launchAtLogin }, set: controller.setLaunchAtLogin
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("退出 LiteControl") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
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
                        Text("发现更多 Lite 应用")
                        Spacer()
                        Text("\(missing.count)").monospacedDigit()
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(height: Self.discoveryHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "已展开" : "已折叠")
                if expanded {
                    ForEach(missing) { product in
                        HStack(spacing: 11) {
                            identity(product)
                            if let repository = product.repository {
                                Link(destination: repository.appendingPathComponent("releases")) {
                                    Label("下载", systemImage: "arrow.down.circle")
                                }
                                .font(.system(size: 12))
                                .help("在 GitHub Releases 下载 \(product.name)")
                                .accessibilityLabel("下载 \(product.name)")
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
                .help("打开 \(product.name) 的 GitHub 仓库")
                .accessibilityLabel("打开 \(product.name) 的 GitHub 仓库")
        } else {
            label
        }
    }

    @ViewBuilder private func locateButton(_ product: LiteProduct) -> some View {
        if case .application = product.control {
            Button("选择 \(product.name).app…") { controller.chooseApplication(product) }
        }
    }

    private func installedRow(_ product: LiteProduct) -> some View {
        HStack(spacing: 11) {
            identity(product)
            if case .postWindow = product.control, controller.postVisible == nil {
                Text(controller.postHost == nil ? "需启动 Hammerspoon" : "控制未连接")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("请启动 Hammerspoon 并加载 LitePost 和 hs.ipc。")
            } else if case .application = product.control {
                Button { controller.chooseApplication(product) } label: {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("选择 \(product.name).app")
                .accessibilityLabel("选择 \(product.name) 的位置")
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
