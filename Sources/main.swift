import Cocoa
import CoreGraphics
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Persistence keys
private enum Key {
    static let interval = "interval"      // seconds (base)
    static let mode = "mode"              // 0 mouse, 1 key, 2 both
    static let randomize = "randomize"    // bool
    static let preventSleep = "preventSleep" // bool
    static let activeOnLaunch = "activeOnLaunch" // bool
}

// MARK: - App
final class AppController: NSObject, NSApplicationDelegate {

    enum Mode: Int { case mouse = 0, key = 1, both = 2 }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0
    private var sleepAssertionActive = false

    private var isRunning = false
    private let defaults = UserDefaults.standard

    // Settings (with defaults: both mode, 120s interval)
    private var baseInterval: TimeInterval {
        get { let v = defaults.double(forKey: Key.interval); return v == 0 ? 120 : v }
        set { defaults.set(newValue, forKey: Key.interval); rescheduleIfNeeded() }
    }
    private var mode: Mode {
        get { Mode(rawValue: defaults.integer(forKey: Key.mode)) ?? .both }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }
    private var randomize: Bool {
        get { defaults.object(forKey: Key.randomize) == nil ? true : defaults.bool(forKey: Key.randomize) }
        set { defaults.set(newValue, forKey: Key.randomize); rescheduleIfNeeded() }
    }
    private var preventSleep: Bool {
        get { defaults.bool(forKey: Key.preventSleep) }
        set { defaults.set(newValue, forKey: Key.preventSleep) }
    }

    private let eventSource = CGEventSource(stateID: .hidSystemState)

    // MARK: Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        buildMenu()
        updateIcon()
        // Optionally start automatically if it was left running.
        if defaults.bool(forKey: Key.activeOnLaunch) {
            start()
        }
    }

    // MARK: Menu
    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshMenu()
    }

    @objc private func refreshMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // Header
        let header = NSMenuItem(title: isRunning ? "● Aktif — uyanık tutuluyor" : "○ Kapalı", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Toggle
        let toggle = NSMenuItem(title: isRunning ? "Durdur" : "Başlat",
                                action: #selector(toggle), keyEquivalent: "s")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        // Mode submenu
        let modeItem = NSMenuItem(title: "Yöntem", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let modes: [(String, Mode)] = [("Mouse + Klavye (F15)", .both), ("Sadece mouse", .mouse), ("Sadece klavye (F15)", .key)]
        for (title, m) in modes {
            let it = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
            it.target = self
            it.tag = m.rawValue
            it.state = (mode == m) ? .on : .off
            modeMenu.addItem(it)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // Interval submenu
        let intervalItem = NSMenuItem(title: "Aralık", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        let intervals: [(String, TimeInterval)] = [("30 saniye", 30), ("60 saniye", 60), ("2 dakika", 120), ("5 dakika", 300)]
        for (title, sec) in intervals {
            let it = NSMenuItem(title: title, action: #selector(setInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sec
            it.state = (abs(baseInterval - sec) < 0.5) ? .on : .off
            intervalMenu.addItem(it)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        // Randomize toggle
        let rnd = NSMenuItem(title: "Rastgele zamanlama (±%50)", action: #selector(toggleRandomize), keyEquivalent: "")
        rnd.target = self
        rnd.state = randomize ? .on : .off
        menu.addItem(rnd)

        // Prevent sleep toggle
        let sleepItem = NSMenuItem(title: "Ekranın uyumasını da engelle", action: #selector(togglePreventSleep), keyEquivalent: "")
        sleepItem.target = self
        sleepItem.state = preventSleep ? .on : .off
        menu.addItem(sleepItem)

        // Launch at login toggle
        let loginItem = NSMenuItem(title: "Girişte otomatik başlat", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Accessibility status
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠︎ Erişilebilirlik izni gerekli — tıkla", action: #selector(requestAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions
    @objc private func toggle() {
        isRunning ? stop() : start()
    }

    private func start() {
        guard !isRunning else { return }
        if !AXIsProcessTrusted() {
            requestAccessibility()
            // Continue anyway; events will start working once permission is granted.
        }
        isRunning = true
        defaults.set(true, forKey: Key.activeOnLaunch)
        scheduleTimer()
        if preventSleep { enableSleepPrevention() }
        updateIcon()
        refreshMenu()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        defaults.set(false, forKey: Key.activeOnLaunch)
        timer?.invalidate(); timer = nil
        disableSleepPrevention()
        updateIcon()
        refreshMenu()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        if let m = Mode(rawValue: sender.tag) { mode = m }
        refreshMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        if let sec = sender.representedObject as? TimeInterval { baseInterval = sec }
        refreshMenu()
    }

    @objc private func toggleRandomize() {
        randomize.toggle()
        refreshMenu()
    }

    @objc private func togglePreventSleep() {
        preventSleep.toggle()
        if isRunning {
            preventSleep ? enableSleepPrevention() : disableSleepPrevention()
        }
        refreshMenu()
    }

    // MARK: Launch at login
    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Giriş öğesi güncellenemedi"
            alert.informativeText = "Uygulamayı /Applications klasörüne taşıyıp tekrar deneyin.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
        refreshMenu()
    }

    @objc private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func quit() {
        disableSleepPrevention()
        NSApp.terminate(nil)
    }

    // MARK: Timer scheduling
    private func rescheduleIfNeeded() {
        if isRunning { scheduleTimer() }
    }

    private func nextDelay() -> TimeInterval {
        guard randomize else { return baseInterval }
        let jitter = baseInterval * 0.5
        return baseInterval + Double.random(in: -jitter...jitter)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let delay = nextDelay()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.jiggle()
            self.scheduleTimer() // re-arm with a fresh (possibly random) delay
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
    }

    // MARK: The actual nudge
    private func jiggle() {
        switch mode {
        case .mouse: nudgeMouse()
        case .key:   pressInertKey()
        case .both:  nudgeMouse(); pressInertKey()
        }
    }

    private func nudgeMouse() {
        let current = currentMouseLocation()
        let dx = CGFloat([-2, -1, 1, 2].randomElement() ?? 1)
        let dy = CGFloat([-2, -1, 1, 2].randomElement() ?? 1)
        let moved = CGPoint(x: current.x + dx, y: current.y + dy)
        postMouseMove(to: moved)
        // Return to original position so the user never notices.
        postMouseMove(to: current)
    }

    private func currentMouseLocation() -> CGPoint {
        // NSEvent uses bottom-left origin; CGEvent uses top-left. Convert via main screen height.
        let p = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: screenHeight - p.y)
    }

    private func postMouseMove(to point: CGPoint) {
        let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved,
                        mouseCursorPosition: point, mouseButton: .left)
        e?.post(tap: .cghidEventTap)
    }

    private func pressInertKey() {
        // F15 (keycode 113) — has no default action in virtually any app.
        let keyCode: CGKeyCode = 113
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Sleep prevention (display + system idle)
    private func enableSleepPrevention() {
        guard !sleepAssertionActive else { return }
        let reason = "JiggleBar keeping the Mac awake" as CFString
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason, &sleepAssertionID)
        sleepAssertionActive = (result == kIOReturnSuccess)
    }

    private func disableSleepPrevention() {
        if sleepAssertionActive {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionActive = false
        }
    }

    // MARK: Icon
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol = isRunning ? "cup.and.saucer.fill" : "cup.and.saucer"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "JiggleBar") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = isRunning ? "☕︎" : "○"
        }
        button.toolTip = isRunning ? "JiggleBar: aktif" : "JiggleBar: kapalı"
    }
}

extension AppController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu() // keep accessibility warning / state fresh
    }
}

// MARK: - Bootstrap
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.run()
