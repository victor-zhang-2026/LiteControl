import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var locations: [String: URL] = [:]
    @Published private(set) var runningIDs = Set<String>()
    @Published private(set) var launchAtLogin = false
    @Published private(set) var postVisible: Bool?
    @Published private(set) var postHost: URL?
    @Published private(set) var busy = Set<String>()
    @Published var message: String?

    private var observation: NSKeyValueObservation?
    private var timer: Timer?
    private var lastDiscovery = Date.distantPast
    private var nextPostProbe = Date.distantPast
    private var postPID: pid_t?
    private var postGeneration = 0
    private var postInFlight = false
    private var queuedPostCommand: PostWindow.Command?
    private var panelVisible = false

    init() {
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.workspaceChanged() }
        }
        refresh()
    }

    deinit { timer?.invalidate() }

    private func workspaceChanged() {
        let prior = runningIDs
        let previousHost = postPID
        refreshProcesses()
        if prior != runningIDs || previousHost != postPID { refresh() }
    }

    private func refreshProcesses() {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let ids = Set(running.compactMap(\.bundleIdentifier))
        let managed = Set(LiteProduct.all.compactMap { product -> String? in
            guard case let .application(id) = product.control, ids.contains(id) else { return nil }
            return id
        })
        if runningIDs != managed { runningIDs = managed }
        let host = running.first { $0.bundleIdentifier == PostWindow.hostID }
        if postPID != host?.processIdentifier {
            postHost = host?.bundleURL
            postPID = host?.processIdentifier
            invalidatePost()
        }
    }

    private func invalidatePost() {
        postGeneration += 1
        postVisible = nil
        queuedPostCommand = nil
        nextPostProbe = .distantPast
    }

    func refresh() {
        refreshProcesses()
        var found: [String: URL] = [:]
        for product in LiteProduct.all {
            switch product.control {
            case let .application(id):
                found[product.id] = ApplicationLocator.find(product, bundleID: id, running: processes(id))
            case .postWindow:
                found[product.id] = PostWindow.installedScript()
                if found[product.id] != locations[product.id] { invalidatePost() }
            }
        }
        if locations != found { locations = found }
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
        lastDiscovery = Date()
        probePostIfNeeded()
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        timer?.invalidate()
        timer = nil
        guard visible else { return }
        nextPostProbe = .distantPast
        refresh()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panelVisible else { return }
                if Date().timeIntervalSince(self.lastDiscovery) >= 10 { self.refresh() }
                else { self.probePostIfNeeded() }
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func processes(_ id: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
    }

    func isRunning(_ product: LiteProduct) -> Bool {
        switch product.control {
        case let .application(id): return runningIDs.contains(id)
        case .postWindow: return postVisible == true
        }
    }

    func canControl(_ product: LiteProduct) -> Bool {
        guard locations[product.id] != nil, !busy.contains(product.id) else { return false }
        if case .postWindow = product.control { return postVisible != nil }
        return true
    }

    func setRunning(_ product: LiteProduct, to desired: Bool) {
        guard canControl(product) else { return }
        switch product.control {
        case .postWindow:
            requestPost(desired ? .show : .hide, product: product)
        case let .application(id):
            let matches = processes(id)
            if desired {
                guard matches.isEmpty else { return }
                guard let url = locations[product.id], ApplicationLocator.matches(url, bundleID: id) else {
                    refresh()
                    return
                }
                busy.insert(product.id)
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                    Task { @MainActor in
                        self?.busy.remove(product.id)
                        if let error { self?.message = String(localized: "Could not start \(product.name): \(error.localizedDescription)") }
                        self?.refresh()
                    }
                }
            } else {
                guard !matches.isEmpty else { return }
                let accepted = matches.map { $0.terminate() }.allSatisfy { $0 }
                if accepted {
                    runningIDs.remove(id)
                    busy.insert(product.id)
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        busy.remove(product.id)
                        refreshProcesses()
                    }
                } else {
                    message = String(localized: "\(product.name) declined the quit request.")
                    refreshProcesses()
                }
            }
        }
    }

    func setAll(to desired: Bool) {
        refresh()
        for product in LiteProduct.all where canControl(product) {
            setRunning(product, to: desired)
        }
    }

    func chooseApplication(_ product: LiteProduct) {
        guard case let .application(id) = product.control else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose \(product.name).app")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = locations[product.id]?.deletingLastPathComponent()
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url, let self else { return }
                guard ApplicationLocator.matches(url, bundleID: id) else {
                    self.message = String(localized: "The selected app does not match the bundle identifier for \(product.name).")
                    return
                }
                UserDefaults.standard.set(url.path, forKey: "applicationPath.\(id)")
                self.message = nil
                self.refresh()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = String(localized: "Could not change the login setting: \(error.localizedDescription)")
        }
        refresh()
    }

    private func probePostIfNeeded() {
        let product = LiteProduct.post
        guard panelVisible, !postInFlight, Date() >= nextPostProbe,
              locations[product.id] != nil, postHost != nil else { return }
        requestPost(.status, product: product)
    }

    private func requestPost(_ command: PostWindow.Command, product: LiteProduct) {
        guard let host = postHost else { return }
        if command != .status { busy.insert(product.id) }
        if postInFlight {
            if command != .status { queuedPostCommand = command }
            return
        }
        let generation = postGeneration
        postInFlight = true
        Task {
            let visible = await PostWindow.request(command, host: host)
            postInFlight = false
            guard generation == postGeneration else {
                busy.remove(product.id)
                probePostIfNeeded()
                return
            }
            if postVisible != visible { postVisible = visible }
            nextPostProbe = Date().addingTimeInterval(visible == nil ? 10 : 1)
            if let queued = queuedPostCommand {
                queuedPostCommand = nil
                requestPost(queued, product: product)
            } else {
                if command != .status {
                    busy.remove(product.id)
                    if visible == nil { message = String(localized: "Check that Hammerspoon has loaded LitePost and hs.ipc.") }
                    else if command == .show && visible == false { message = String(localized: "LitePost could not open. Check its storage folder.") }
                    else { message = nil }
                }
            }
        }
    }
}
