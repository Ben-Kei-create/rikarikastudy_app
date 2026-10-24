import UIKit
import SwiftUI

/// A small ripple-and-sparkle burst wherever the screen is touched. It only observes touches (its
/// recogniser fails at once and never cancels or delays anything), so buttons, scrolling and drags behave
/// exactly as before. Honours the in-app 演出 switch and the system Reduce Motion setting.
@MainActor
final class TouchEffects {
    static let shared = TouchEffects()

    /// Set while a full-screen ad is up: nothing may be drawn over an ad.
    var suppressed = false

    /// Test override; nil = follow the real settings.
    var enabledOverride: Bool?
    var isEnabled: Bool {
        if let o = enabledOverride { return o }
        return AppSettings.shared.effectsEnabled && !UIAccessibility.isReduceMotionEnabled && !suppressed
    }

    private weak var installedWindow: UIWindow?
    private let overlay = PassthroughView()

    func install(in window: UIWindow) {
        guard installedWindow !== window else { return }
        installedWindow = window
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        let observer = TouchObserver()
        observer.onTouch = { [weak self] point in self?.burst(at: point) }
        window.addGestureRecognizer(observer)
    }

    func burst(at point: CGPoint) {
        guard isEnabled, let window = installedWindow else { return }
        window.bringSubviewToFront(overlay)
        let p = overlay.convert(point, from: window)
        let ring = CAShapeLayer()
        let r: CGFloat = 12
        ring.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).cgPath
        ring.position = p
        ring.fillColor = UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 0.4).cgColor
        ring.strokeColor = UIColor(red: 1, green: 0.85, blue: 0.45, alpha: 1).cgColor
        ring.lineWidth = 4
        overlay.layer.addSublayer(ring)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4; scale.toValue = 3.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.6
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ripple")
        ring.opacity = 0
        CATransaction.commit()

        // Six little sparks flying outward.
        for i in 0..<6 {
            let angle = CGFloat(i) / 6 * 2 * .pi + CGFloat.random(in: -0.25...0.25)
            let dist = CGFloat.random(in: 36...64)
            let spark = CAShapeLayer()
            let s: CGFloat = CGFloat.random(in: 3.5...6)
            spark.path = UIBezierPath(ovalIn: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s)).cgPath
            spark.position = p
            spark.fillColor = (i % 2 == 0 ? UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1) : UIColor.white).cgColor
            overlay.layer.addSublayer(spark)
            CATransaction.begin()
            CATransaction.setCompletionBlock { spark.removeFromSuperlayer() }
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = p
            move.toValue = CGPoint(x: p.x + cos(angle) * dist, y: p.y + sin(angle) * dist)
            let fadeS = CABasicAnimation(keyPath: "opacity")
            fadeS.fromValue = 1; fadeS.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [move, fadeS]
            g.duration = 0.65
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            spark.add(g, forKey: "spark")
            spark.opacity = 0
            CATransaction.commit()
        }
    }
}

/// Never takes a touch: everything passes through to the app underneath.
private final class PassthroughView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Reports where each touch begins, then fails immediately so it can never interfere with other gestures.
private final class TouchObserver: UIGestureRecognizer {
    var onTouch: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { onTouch?(t.location(in: view)) }
        state = .failed
    }
}

/// Put in a SwiftUI background once; attaches the touch effect to the hosting window.
struct TouchEffectInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { MainActor.assumeIsolated { TouchEffects.shared.install(in: window) } }
        }
    }
}
