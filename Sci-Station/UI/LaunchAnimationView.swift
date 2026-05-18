import AppKit
import SwiftUI

struct SciStationLaunchAnimationView: NSViewRepresentable {
    func makeNSView(context: Context) -> SciStationLiquidLaunchView {
        SciStationLiquidLaunchView()
    }

    func updateNSView(_ nsView: SciStationLiquidLaunchView, context: Context) {}
}

final class SciStationLiquidLaunchView: NSView {
    private let backlightLayer = CAGradientLayer()
    private let colorBloomLayer = CAGradientLayer()
    private let panelLayer = CALayer()
    private let materialHostView = NSView()
    private let materialView = NSVisualEffectView()
    private let materialMaskLayer = CAShapeLayer()
    private let overlayView = NSView()
    private let panelTintLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    private let titleBackLayer = CATextLayer()
    private let titleMidLayer = CATextLayer()
    private let titleFrontLayer = CATextLayer()

    private var didStartAnimation = false

    private var startFrame: CGRect {
        let side: CGFloat = 132
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    private var finalFrame: CGRect {
        let width = min(bounds.width * 0.82, 520)
        let height: CGFloat = 172
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = false
        startAnimationIfNeeded()
    }

    override func layout() {
        super.layout()

        if didStartAnimation {
            applyFinalLayout()
        } else {
            applyStartLayout()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        startAnimationIfNeeded()
    }

    private func setupLayers() {
        guard let layer else { return }
        layer.masksToBounds = false
        layer.backgroundColor = NSColor.clear.cgColor

        backlightLayer.colors = [
            NSColor.systemBlue.withAlphaComponent(0.18).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.12).cgColor,
            NSColor.systemTeal.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        backlightLayer.locations = [0, 0.34, 0.64, 1]
        backlightLayer.startPoint = CGPoint(x: 0.05, y: 1)
        backlightLayer.endPoint = CGPoint(x: 1, y: 0)
        backlightLayer.opacity = 0.42
        backlightLayer.allowsEdgeAntialiasing = true
        layer.addSublayer(backlightLayer)

        colorBloomLayer.colors = [
            NSColor.systemCyan.withAlphaComponent(0.14).cgColor,
            NSColor.systemPink.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        colorBloomLayer.locations = [0, 0.42, 1]
        colorBloomLayer.startPoint = CGPoint(x: 0, y: 0.18)
        colorBloomLayer.endPoint = CGPoint(x: 1, y: 0.86)
        colorBloomLayer.opacity = 0.26
        colorBloomLayer.allowsEdgeAntialiasing = true
        layer.addSublayer(colorBloomLayer)

        panelLayer.backgroundColor = NSColor.white.withAlphaComponent(0.004).cgColor
        panelLayer.shadowColor = NSColor.black.cgColor
        panelLayer.shadowOpacity = 0.16
        panelLayer.shadowRadius = 14
        panelLayer.shadowOffset = CGSize(width: 0, height: -3)
        panelLayer.allowsEdgeAntialiasing = true
        panelLayer.drawsAsynchronously = true
        layer.addSublayer(panelLayer)

        materialHostView.wantsLayer = true
        materialHostView.alphaValue = 0.52
        materialHostView.layer?.backgroundColor = NSColor.clear.cgColor
        materialHostView.layer?.mask = materialMaskLayer
        materialHostView.layer?.allowsEdgeAntialiasing = true
        addSubview(materialHostView)

        materialMaskLayer.fillColor = NSColor.black.cgColor
        materialMaskLayer.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]

        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.isEmphasized = true
        materialView.wantsLayer = true
        materialView.layer?.backgroundColor = NSColor.clear.cgColor
        materialView.layer?.allowsEdgeAntialiasing = true
        materialHostView.addSubview(materialView)

        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayView.layer?.masksToBounds = false
        addSubview(overlayView)

        panelTintLayer.colors = [
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.systemCyan.withAlphaComponent(0.08).cgColor,
            NSColor.systemBlue.withAlphaComponent(0.05).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.045).cgColor
        ]
        panelTintLayer.locations = [0, 0.32, 0.72, 1]
        panelTintLayer.startPoint = CGPoint(x: 0.08, y: 1)
        panelTintLayer.endPoint = CGPoint(x: 0.95, y: 0)
        panelTintLayer.opacity = 0.32
        panelTintLayer.masksToBounds = true
        panelTintLayer.allowsEdgeAntialiasing = true
        overlayView.layer?.addSublayer(panelTintLayer)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.white.withAlphaComponent(0.035).cgColor,
            NSColor.white.withAlphaComponent(0.012).cgColor
        ]
        sheenLayer.locations = [0, 0.45, 1]
        sheenLayer.startPoint = CGPoint(x: 0.12, y: 1)
        sheenLayer.endPoint = CGPoint(x: 0.92, y: 0)
        sheenLayer.opacity = 0.4
        sheenLayer.masksToBounds = true
        sheenLayer.allowsEdgeAntialiasing = true
        overlayView.layer?.addSublayer(sheenLayer)

        rimLayer.fillColor = NSColor.clear.cgColor
        rimLayer.strokeColor = NSColor.white.withAlphaComponent(0.42).cgColor
        rimLayer.lineWidth = 1.15
        rimLayer.allowsEdgeAntialiasing = true
        overlayView.layer?.addSublayer(rimLayer)

        configureTitleLayer(titleBackLayer, color: NSColor.systemCyan.withAlphaComponent(0.58), offset: CGPoint(x: -4, y: 3))
        configureTitleLayer(titleMidLayer, color: NSColor.systemPurple.withAlphaComponent(0.48), offset: CGPoint(x: 4, y: -3))
        configureTitleLayer(titleFrontLayer, color: .white, offset: .zero)
    }

    private func configureTitleLayer(_ textLayer: CATextLayer, color: NSColor, offset: CGPoint) {
        textLayer.string = "Sci-Station"
        textLayer.font = preferredTitleFontName() as CFString
        textLayer.fontSize = 70
        textLayer.alignmentMode = .center
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.foregroundColor = color.cgColor
        textLayer.opacity = 0
        if textLayer === titleFrontLayer {
            textLayer.shadowColor = NSColor.black.withAlphaComponent(0.42).cgColor
            textLayer.shadowOpacity = 0.34
            textLayer.shadowRadius = 6
            textLayer.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            textLayer.shadowColor = color.cgColor
            textLayer.shadowOpacity = 0.18
            textLayer.shadowRadius = 4
            textLayer.shadowOffset = .zero
        }
        textLayer.actions = ["contents": NSNull()]
        textLayer.setAffineTransform(CGAffineTransform(translationX: offset.x, y: offset.y))
        overlayView.layer?.addSublayer(textLayer)
    }

    private func preferredTitleFontName() -> String {
        if NSFont(name: "SnellRoundhand-Bold", size: 70) != nil {
            return "SnellRoundhand-Bold"
        }
        if NSFont(name: "Snell Roundhand", size: 70) != nil {
            return "Snell Roundhand"
        }
        return "HelveticaNeue-Medium"
    }

    private func applyStartLayout() {
        let frame = startFrame
        applyPanelFrame(frame, cornerRadius: frame.width / 2)
        applyTitleFrame(finalFrame, opacity: 0)
    }

    private func applyFinalLayout() {
        let frame = finalFrame
        applyPanelFrame(frame, cornerRadius: 28)
        applyTitleFrame(frame, opacity: 1)
    }

    private func applyPanelFrame(_ frame: CGRect, cornerRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        panelLayer.frame = frame
        panelLayer.cornerRadius = cornerRadius
        let shadowRect = CGRect(origin: .zero, size: frame.size).insetBy(dx: 2, dy: 2)
        let shadowRadius = max(cornerRadius - 2, 0)
        panelLayer.shadowPath = CGPath(roundedRect: shadowRect, cornerWidth: shadowRadius, cornerHeight: shadowRadius, transform: nil)

        materialHostView.frame = bounds
        materialHostView.layer?.mask = materialMaskLayer
        materialView.frame = materialHostView.bounds
        materialMaskLayer.frame = materialHostView.bounds
        materialMaskLayer.path = CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        overlayView.frame = bounds

        let glowFrame = frame.insetBy(dx: -22, dy: -16)
        backlightLayer.frame = glowFrame
        backlightLayer.cornerRadius = cornerRadius + 18

        let bloomFrame = frame.insetBy(dx: -10, dy: -8)
        colorBloomLayer.frame = bloomFrame
        colorBloomLayer.cornerRadius = cornerRadius + 10

        panelTintLayer.frame = frame
        panelTintLayer.cornerRadius = cornerRadius

        sheenLayer.frame = frame
        sheenLayer.cornerRadius = cornerRadius

        rimLayer.frame = overlayView.bounds
        rimLayer.path = CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        CATransaction.commit()
    }

    private func applyTitleFrame(_ frame: CGRect, opacity: Float) {
        let titleHeight: CGFloat = 92
        let titleFrame = CGRect(
            x: frame.minX + 28,
            y: frame.midY - titleHeight / 2 - 2,
            width: frame.width - 56,
            height: titleHeight
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [titleBackLayer, titleMidLayer, titleFrontLayer].forEach { textLayer in
            textLayer.frame = titleFrame
            textLayer.opacity = opacity
        }
        CATransaction.commit()
    }

    private func startAnimationIfNeeded() {
        guard !didStartAnimation, window != nil, layer != nil else { return }
        didStartAnimation = true
        layoutSubtreeIfNeeded()

        let fromFrame = startFrame
        let toFrame = finalFrame
        let fromRadius = fromFrame.width / 2
        let toRadius: CGFloat = 28
        let timing = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.18, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyPanelFrame(toFrame, cornerRadius: toRadius)
        applyTitleFrame(toFrame, opacity: 1)
        CATransaction.commit()

        animateFrame(backlightLayer, from: fromFrame.insetBy(dx: -16, dy: -14), to: toFrame.insetBy(dx: -22, dy: -16), fromRadius: fromRadius + 14, toRadius: toRadius + 18, timing: timing)
        animateFrame(colorBloomLayer, from: fromFrame.insetBy(dx: -8, dy: -8), to: toFrame.insetBy(dx: -10, dy: -8), fromRadius: fromRadius + 8, toRadius: toRadius + 10, timing: timing)
        animateFrame(panelLayer, from: fromFrame, to: toFrame, fromRadius: fromRadius, toRadius: toRadius, timing: timing)
        animateFrame(panelTintLayer, from: fromFrame, to: toFrame, fromRadius: fromRadius, toRadius: toRadius, timing: timing)
        animateFrame(sheenLayer, from: fromFrame, to: toFrame, fromRadius: fromRadius, toRadius: toRadius, timing: timing)

        animate(
            materialMaskLayer,
            keyPath: "path",
            from: CGPath(roundedRect: fromFrame, cornerWidth: fromRadius, cornerHeight: fromRadius, transform: nil),
            to: CGPath(roundedRect: toFrame, cornerWidth: toRadius, cornerHeight: toRadius, transform: nil),
            duration: 0.86,
            timing: timing
        )

        animate(
            rimLayer,
            keyPath: "path",
            from: CGPath(roundedRect: fromFrame, cornerWidth: fromRadius, cornerHeight: fromRadius, transform: nil),
            to: CGPath(roundedRect: toFrame, cornerWidth: toRadius, cornerHeight: toRadius, transform: nil),
            duration: 0.86,
            timing: timing
        )

        animate(panelTintLayer, keyPath: "opacity", from: 0.1, to: 0.32, duration: 0.58, beginTime: 0.14, timing: timing)
        animate(sheenLayer, keyPath: "opacity", from: 0.1, to: 0.4, duration: 0.54, beginTime: 0.18, timing: timing)
        animate(backlightLayer, keyPath: "opacity", from: 0.16, to: 0.42, duration: 0.62, beginTime: 0.1, timing: timing)
        animate(colorBloomLayer, keyPath: "opacity", from: 0.08, to: 0.26, duration: 0.62, beginTime: 0.18, timing: timing)
        animateTitle()
    }

    private func animateTitle() {
        let layers = [titleBackLayer, titleMidLayer, titleFrontLayer]
        for (index, textLayer) in layers.enumerated() {
            animate(textLayer, keyPath: "opacity", from: 0, to: textLayer.opacity, duration: 0.5, beginTime: 0.66 + Double(index) * 0.045, timing: .init(name: .easeOut))
            animate(textLayer, keyPath: "transform.scale", from: 0.965, to: 1, duration: 0.58, beginTime: 0.66 + Double(index) * 0.045, timing: .init(name: .easeOut))
        }
    }

    private func animateFrame(
        _ layer: CALayer,
        from fromFrame: CGRect,
        to toFrame: CGRect,
        fromRadius: CGFloat,
        toRadius: CGFloat,
        timing: CAMediaTimingFunction
    ) {
        animate(layer, keyPath: "bounds", from: CGRect(origin: .zero, size: fromFrame.size), to: CGRect(origin: .zero, size: toFrame.size), duration: 0.86, timing: timing)
        animate(layer, keyPath: "position", from: CGPoint(x: fromFrame.midX, y: fromFrame.midY), to: CGPoint(x: toFrame.midX, y: toFrame.midY), duration: 0.86, timing: timing)
        animate(layer, keyPath: "cornerRadius", from: fromRadius, to: toRadius, duration: 0.86, timing: timing)
    }

    private func animate(
        _ layer: CALayer,
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval,
        beginTime: CFTimeInterval = 0,
        timing: CAMediaTimingFunction
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + beginTime
        animation.timingFunction = timing
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: keyPath)
    }
}

struct SciStationLaunchAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        SciStationLaunchAnimationView()
            .frame(width: 620, height: 360)
            .background(Color.black)
    }
}
