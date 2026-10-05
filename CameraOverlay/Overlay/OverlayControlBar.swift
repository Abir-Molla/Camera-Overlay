import AppKit

/// Floating, non-activating strip shown under the camera bubble on hover.
/// Excluded from screen capture, so it never shows up in recordings.
final class OverlayControlPanel: NSPanel {
    let bar = ControlBarView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sharingType = .none // keep it out of recordings and screenshots
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = bar
        sizeToFit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resizes the panel to the bar's current content.
    func sizeToFit() {
        bar.layoutSubtreeIfNeeded()
        setContentSize(bar.fittingSize)
        invalidateShadow()
    }
}

/// The control strip itself. Built with AppKit so buttons react to the first click
/// even though the panel never becomes key and never activates the app.
final class ControlBarView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onFullScreen: (() -> Void)?
    var onRecord: (() -> Void)?
    var onCountdown: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHide: (() -> Void)?

    private let stack = NSStackView()
    private let fullScreenButton = ControlBarButton(symbol: "arrow.up.left.and.arrow.down.right", tooltip: "Full Screen")
    private let recordButton = ControlBarButton(symbol: "record.circle", tooltip: "Start Recording", tint: .systemRed)
    private let countdownButton = ControlBarButton(symbol: "timer", tooltip: "Record after a \(RecordingController.countdownSeconds)-second countdown")
    private let pauseButton = ControlBarButton(symbol: "pause.fill", tooltip: "Pause")
    private let stopButton = ControlBarButton(symbol: "stop.fill", tooltip: "Stop & Save", tint: .systemRed)
    private let cancelButton = ControlBarButton(symbol: "xmark", tooltip: "Cancel")
    private let hideButton = ControlBarButton(symbol: "eye.slash", tooltip: "Hide Camera (show again from the menu bar)")
    private let separator = NSView()
    private let trailingSeparator = NSView()
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.94).cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor

        for line in [separator, trailingSeparator] {
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalToConstant: 1),
                line.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
        ])

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        fullScreenButton.target = self
        fullScreenButton.action = #selector(fullScreenTapped)
        recordButton.target = self
        recordButton.action = #selector(recordTapped)
        countdownButton.target = self
        countdownButton.action = #selector(countdownTapped)
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        hideButton.target = self
        hideButton.action = #selector(hideTapped)

        update(state: .idle, elapsed: 0, isFullScreen: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(state: RecordingController.State, elapsed: TimeInterval, isFullScreen: Bool) {
        fullScreenButton.symbol = isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullScreenButton.toolTip = isFullScreen ? "Exit Full Screen" : "Full Screen"

        let views: [NSView]
        switch state {
        case .idle:
            views = [fullScreenButton, separator, recordButton, countdownButton, trailingSeparator, hideButton]
        case .countingDown(let remaining):
            statusLabel.stringValue = "Recording in \(remaining)…"
            views = [statusLabel, cancelButton]
        case .starting:
            statusLabel.stringValue = "Starting…"
            views = [statusLabel]
        case .recording:
            statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            statusLabel.stringValue = Self.format(elapsed)
            pauseButton.symbol = "pause.fill"
            pauseButton.toolTip = "Pause"
            views = [fullScreenButton, separator, statusDot, statusLabel, pauseButton, stopButton, trailingSeparator, hideButton]
        case .paused:
            statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
            statusLabel.stringValue = Self.format(elapsed)
            pauseButton.symbol = "play.fill"
            pauseButton.toolTip = "Resume"
            views = [fullScreenButton, separator, statusDot, statusLabel, pauseButton, stopButton, trailingSeparator, hideButton]
        case .saving:
            statusLabel.stringValue = "Saving…"
            views = [statusLabel]
        }
        setArrangedViews(views)
    }

    private func setArrangedViews(_ views: [NSView]) {
        guard stack.arrangedSubviews != views else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
        // Text and buttons need a little breathing room from each other.
        // Only views currently in the stack may get custom spacing (NSStackView asserts otherwise).
        let spacing: [(NSView, CGFloat)] = [(separator, 8), (statusDot, 6), (statusLabel, 8), (stopButton, 8), (countdownButton, 8), (trailingSeparator, 8)]
        for (view, value) in spacing where views.contains(view) {
            stack.setCustomSpacing(value, after: view)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    // MARK: Actions

    @objc private func fullScreenTapped() { onFullScreen?() }
    @objc private func recordTapped() { onRecord?() }
    @objc private func countdownTapped() { onCountdown?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func stopTapped() { onStop?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func hideTapped() { onHide?() }
}

/// Icon-only button with a subtle hover highlight.
final class ControlBarButton: NSButton {
    var symbol: String {
        didSet { updateImage() }
    }

    private let tint: NSColor
    private var hoverArea: NSTrackingArea?

    init(symbol: String, tooltip: String, tint: NSColor = .white) {
        self.symbol = symbol
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 28))
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        updateImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateImage() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?.withSymbolConfiguration(configuration)
        contentTintColor = tint
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }
}
