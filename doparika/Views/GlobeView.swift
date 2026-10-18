import SwiftUI
import SceneKit

/// Slowly spinning Earth (baked USDZ from tools/blender/make_globe.py) on a transparent background.
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
        view.isUserInteractionEnabled = false
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
        applySpin(view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) { applySpin(view) }

    private func applySpin(_ view: SCNView) {
        guard let spinner = view.scene?.rootNode.childNode(withName: "spinner", recursively: false) else { return }
        spinner.removeAllActions()
        if spins {
            spinner.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.spinPeriod)))
        }
        view.isPlaying = spins
    }
}
