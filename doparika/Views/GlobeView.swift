import SwiftUI
import SceneKit

/// Earth (baked USDZ from tools/blender/make_globe.py) on a transparent background.
/// Drag to spin it in any direction like a desk globe; a flick keeps it turning with inertia, then it
/// settles back to the slow idle spin. The globe itself never moves on screen.
struct GlobeView: UIViewRepresentable {
    var spins = true
    /// Seconds for one full turn.
    static let spinPeriod: Double = 28

    static func loadScene() -> SCNScene? {
        guard let url = Bundle.main.url(forResource: "globe", withExtension: "usdz"),
              let scene = try? SCNScene(url: url) else { return nil }
        return scene
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = true
        guard let scene = Self.loadScene() else { return view }
        scene.background.contents = UIColor.clear

        let earth = SCNNode()
        for child in scene.rootNode.childNodes { earth.addChildNode(child) }
        earth.name = "earth"
        earth.eulerAngles.z = Float(23.4 * .pi / 180)           // axial tilt
        let spinner = SCNNode()
        spinner.addChildNode(earth)
        spinner.name = "spinner"
        scene.rootNode.addChildNode(spinner)

        // Thin atmosphere halo.
        let halo = SCNSphere(radius: 1.07)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 0.18)
        m.emission.contents = UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 0.25)
        m.isDoubleSided = true
        m.blendMode = .add
        m.writesToDepthBuffer = false
        halo.materials = [m]
        scene.rootNode.addChildNode(SCNNode(geometry: halo))

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 32
        cam.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(cam)

        let sun = SCNNode()
        sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 1700
        sun.eulerAngles = SCNVector3(-0.35, -0.9, 0)
        scene.rootNode.addChildNode(sun)
        let amb = SCNNode()
        amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 260
        amb.light?.color = UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1)
        scene.rootNode.addChildNode(amb)

        view.scene = scene
        view.pointOfView = cam
        context.coordinator.attach(view: view, spinner: spinner)
        context.coordinator.idleSpin = spins
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.idleSpin = spins }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) { coordinator.detach() }

    /// Integrates the globe's angular velocity once per frame (main thread display link).
    @MainActor
    final class Coordinator: NSObject {
        private weak var view: SCNView?
        private var spinner: SCNNode?
        private var link: CADisplayLink?
        private var lastTime: CFTimeInterval = 0
        private var dragging = false
        /// Angular velocity in world space (rad/s).
        private var omega = SIMD3<Float>(0, 0, 0)
        private let radiansPerPoint: Float = 0.013      // ≈ 1 / on-screen globe radius
        private let maxSpeed: Float = 14
        private let idleSpeed = Float(2 * Double.pi / GlobeView.spinPeriod)

        var idleSpin = true { didSet { if idleSpin { startLink() } } }

        func attach(view: SCNView, spinner: SCNNode) {
            self.view = view
            self.spinner = spinner
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            view.addGestureRecognizer(pan)
            omega = SIMD3(0, idleSpeed, 0)
            startLink()
        }

        func detach() { link?.invalidate(); link = nil }

        private func startLink() {
            guard link == nil, view != nil else { return }
            lastTime = 0
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        private func rotate(by delta: SIMD3<Float>) {
            let angle = simd_length(delta)
            guard angle > 1e-6, let spinner else { return }
            spinner.simdOrientation = simd_quatf(angle: angle, axis: delta / angle) * spinner.simdOrientation
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began:
                dragging = true
                omega = .zero
                startLink()
            case .changed:
                let t = g.translation(in: v)
                g.setTranslation(.zero, in: v)
                // Drag right -> surface moves right (spin about +Y); drag down -> about +X.
                rotate(by: SIMD3(Float(t.y), Float(t.x), 0) * radiansPerPoint)
            case .ended, .cancelled, .failed:
                dragging = false
                let vel = g.velocity(in: v)
                var w = SIMD3(Float(vel.y), Float(vel.x), 0) * radiansPerPoint
                let speed = simd_length(w)
                if speed > maxSpeed { w *= maxSpeed / speed }
                omega = w
            default: break
            }
        }

        @objc private func tick(_ l: CADisplayLink) {
            let now = l.timestamp
            let dt = lastTime == 0 ? 1.0 / 60 : Float(min(now - lastTime, 0.05))
            lastTime = now
            guard !dragging else { return }
            let target = idleSpin ? SIMD3<Float>(0, idleSpeed, 0) : .zero
            omega += (target - omega) * Float(1 - exp(-Double(dt) * 1.1))   // inertia fades out smoothly
            rotate(by: omega * dt)
            if !idleSpin, simd_length(omega) < 0.01 { omega = .zero; link?.invalidate(); link = nil }
        }
    }
}
