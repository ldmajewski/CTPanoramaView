//
//  CTPanoramaView
//  CTPanoramaView
//
//  Created by Cihan Tek on 11/10/16.
//  Copyright © 2016 Home. All rights reserved.
//

import UIKit
import SceneKit
import CoreMotion
import ImageIO

@objc public protocol CTPanoramaCompass {
    func updateUI(rotationAngle: CGFloat, fieldOfViewAngle: CGFloat)
}

@objc public protocol CTPanoramaHotspotDelegate {
    func hotspotTapped(name: String)
}

@objc public enum CTPanoramaControlMethod: Int {
    case motion
    case touch
}

@objc public enum CTPanoramaType: Int {
    case cylindrical
    case spherical
}

@objc public enum CTPanoramaHotspotType: Int {
    case ground
    case hover
}

@objc public class CTPanoramaView: UIView {
    
    // MARK: Public properties
    
    public var panSpeed = CGPoint(x: 0.005, y: 0.005)
    
    public var image: UIImage? {
        didSet {
            panoramaType = panoramaTypeForCurrentImage
        }
    }
    
    public var hotspotImage: UIImage? {
        didSet {
            createHotspotNodes()
        }
    }
    
    public var hotspots: [String:Float]? {
        didSet {
            createHotspotNodes()
        }
    }
    
    public var hotspotType: CTPanoramaHotspotType = .ground {
        didSet {
            createHotspotNodes()
        }
    }
    
    public var overlayView: UIView? {
        didSet {
            replace(overlayView: oldValue, with: overlayView)
        }
    }
    
    public var panoramaType: CTPanoramaType = .cylindrical {
        didSet {
            createGeometryNode()
            resetCameraAngles()
        }
    }
    
    public var controlMethod: CTPanoramaControlMethod! {
        didSet {
            switchControlMethod(to: controlMethod!)
            resetCameraAngles()
        }
    }
    
    public var compass: CTPanoramaCompass?
    public var hotspotDelegate: CTPanoramaHotspotDelegate?
    public var movementHandler: ((_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat) -> ())?
    
    // MARK: Private properties
    
    private let radius: CGFloat = 10
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private let motionManager = CMMotionManager()
    private var geometryNode: SCNNode?
    private var hotspotsNodes: [SCNNode] = []
    private var prevLocation = CGPoint.zero
    private var prevBounds = CGRect.zero
    
    private lazy var cameraNode: SCNNode = {
        let node = SCNNode()
        let camera = SCNCamera()
        camera.yFov = 70
        node.camera = camera
        return node
    }()
    
    private lazy var fovHeight: CGFloat = {
        return CGFloat(tan(self.cameraNode.camera!.yFov/2 * .pi / 180.0)) * 2 * self.radius
    }()
    
    private var xFov: CGFloat {
        return CGFloat(self.cameraNode.camera!.yFov) * self.bounds.width / self.bounds.height
    }
    
    private var panoramaTypeForCurrentImage: CTPanoramaType {
        if let image = image {
            if image.size.width / image.size.height == 2 {
                return .spherical
            }
        }
        return .cylindrical
    }
    
    // MARK: Class lifecycle methods
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public convenience init(frame: CGRect, image: UIImage) {
        self.init(frame: frame)
        ({self.image = image})() // Force Swift to call the property observer by calling the setter from a non-init context
    }
    
    deinit {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    
    private func commonInit() {
        add(view: sceneView)
    
        scene.rootNode.addChildNode(cameraNode)
        
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor.black
        sceneView.antialiasingMode = .multisampling4X
        
        if controlMethod == nil {
            controlMethod = .touch
        }
     }
    
    // MARK: Configuration helper methods

    private func createGeometryNode() {
        guard let image = image else {return}
        
        geometryNode?.removeFromParentNode()
        
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 1.0
        material.diffuse.magnificationFilter = .linear
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        material.diffuse.wrapS = .repeat
        material.cullMode = .front
        
        if panoramaType == .spherical {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 300
            sphere.firstMaterial = material
            
            let sphereNode = SCNNode()
            sphereNode.geometry = sphere
            geometryNode = sphereNode
        }
        else {
            let tube = SCNTube(innerRadius: radius, outerRadius: radius, height: fovHeight)
            tube.heightSegmentCount = 50
            tube.radialSegmentCount = 300
            tube.firstMaterial = material
            
            let tubeNode = SCNNode()
            tubeNode.geometry = tube
            geometryNode = tubeNode
        }
        scene.rootNode.addChildNode(geometryNode!)
    }
    
    private func createHotspotNodes() {
        guard let hotspotImage = hotspotImage else {return}
        guard let hotspots = hotspots else {return}
        
        for node in hotspotsNodes {
            node.removeFromParentNode()
        }
        hotspotsNodes.removeAll()
        
        let material = SCNMaterial()
        material.diffuse.contents = hotspotImage
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 1.0
        material.diffuse.magnificationFilter = .linear
        material.isDoubleSided = true
        
        for (name,angle) in hotspots {
            let node = createHotspotNode(angle: angle.toRadians(), material: material)
            node.name = name
            scene.rootNode.addChildNode(node)
            hotspotsNodes.append(node)
        }
    }
    
    private func createHotspotNode(angle:Float, material:SCNMaterial) -> SCNNode {
        let hotspot = SCNPlane(width: 1.0, height: 1.0)
        hotspot.firstMaterial = material
        
        let hotspotNode = SCNNode()
        hotspotNode.geometry = hotspot
        hotspotNode.position = hotspotPosition(angle:angle, radius: Float(radius/2))
        
        var pitch:Float = 0
        
        if hotspotType == .ground {
            pitch = Float(-45).toRadians()
        }
        
        hotspotNode.eulerAngles = SCNVector3Make(pitch, Float(90).toRadians()-angle, 0)
        
        return hotspotNode
    }
    
    private func hotspotPosition(angle:Float, radius:Float) -> SCNVector3 {
        return SCNVector3Make(cos(angle)*radius, -radius/3, sin(angle)*radius)
    }
    
    private func replace(overlayView: UIView?, with newOverlayView: UIView?) {
        overlayView?.removeFromSuperview()
        guard let newOverlayView = newOverlayView else {return}
        add(view: newOverlayView)
    }
    
    private func switchControlMethod(to method: CTPanoramaControlMethod) {
        sceneView.gestureRecognizers?.removeAll()

        let tapGestureRec = UITapGestureRecognizer(target: self, action: #selector(handleTap(tapRec:)))
        sceneView.addGestureRecognizer(tapGestureRec)
        
        if method == .touch {
                let panGestureRec = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panRec:)))
                sceneView.addGestureRecognizer(panGestureRec)
 
            if motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
            }
        }
        else {
            guard motionManager.isDeviceMotionAvailable else {return}
            motionManager.deviceMotionUpdateInterval = 0.015
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: OperationQueue.main, withHandler: {[weak self] (motionData, error) in
                guard let panoramaView = self else {return}
                guard panoramaView.controlMethod == .motion else {return}
                
                guard let motionData = motionData else {
                    print("\(error?.localizedDescription)")
                    panoramaView.motionManager.stopDeviceMotionUpdates()
                    return
                }
                
                let rm = motionData.attitude.rotationMatrix
                var userHeading = .pi - atan2(rm.m32, rm.m31)
                userHeading += .pi/2
                
                if panoramaView.panoramaType == .cylindrical {
                    panoramaView.cameraNode.eulerAngles = SCNVector3Make(0, Float(-userHeading), 0) // Prevent vertical movement in a cylindrical panorama
                }
                else {
                    // Use quaternions when in spherical mode to prevent gimbal lock
                    panoramaView.cameraNode.orientation = motionData.orientation()
                }
                panoramaView.reportMovement(CGFloat(userHeading), panoramaView.xFov.toRadians())
            })
        }
    }
    
    private func resetCameraAngles() {
        cameraNode.eulerAngles = SCNVector3Make(0, 0, 0)
        self.reportMovement(0, xFov.toRadians(), callHandler: false)
    }
    
    private func reportMovement(_ rotationAngle: CGFloat, _ fieldOfViewAngle: CGFloat, callHandler: Bool = true) {
        compass?.updateUI(rotationAngle: rotationAngle, fieldOfViewAngle: fieldOfViewAngle)
        if callHandler {
            movementHandler?(rotationAngle, fieldOfViewAngle)
        }
    }
    
    // MARK: Gesture handling
    
    @objc private func handlePan(panRec: UIPanGestureRecognizer) {
        if panRec.state == .began {
            prevLocation = CGPoint.zero
        }
        else if panRec.state == .changed {
            var modifiedPanSpeed = panSpeed
            
            if panoramaType == .cylindrical {
                modifiedPanSpeed.y = 0 // Prevent vertical movement in a cylindrical panorama
            }
            
            let location = panRec.translation(in: sceneView)
            let orientation = cameraNode.eulerAngles
            var newOrientation = SCNVector3Make(orientation.x + Float(location.y - prevLocation.y) * Float(modifiedPanSpeed.y),
                                                orientation.y + Float(location.x - prevLocation.x) * Float(modifiedPanSpeed.x),
                                                orientation.z)
            
            if controlMethod == .touch {
                newOrientation.x = max(min(newOrientation.x, 1.1),-1.1)
            }

            cameraNode.eulerAngles = newOrientation
            prevLocation = location
            
            reportMovement(CGFloat(-cameraNode.eulerAngles.y), xFov.toRadians())
        }
    }
    
    @objc private func handleTap(tapRec: UITapGestureRecognizer) {
        let hitResults = sceneView.hitTest(tapRec.location(in: sceneView), options: nil)
        
        if let result = hitResults.first {
            let node = result.node
            
            if node != geometryNode {
                hotspotDelegate?.hotspotTapped(name: node.name!)
            }
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size.width != prevBounds.size.width || bounds.size.height != prevBounds.size.height {
            sceneView.setNeedsDisplay()
            reportMovement(CGFloat(-cameraNode.eulerAngles.y), xFov.toRadians(), callHandler: false)
        }
    }
}

fileprivate extension CMDeviceMotion {
    
        func orientation() -> SCNVector4 {
        
        let attitude = self.attitude.quaternion
        let aq = GLKQuaternionMake(Float(attitude.x), Float(attitude.y), Float(attitude.z), Float(attitude.w))
        
        var result: SCNVector4
        
        switch UIApplication.shared.statusBarOrientation {
            
        case .landscapeRight:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(.pi/2, 0, 1, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            var q = GLKQuaternionMultiply(cq1, aq)
            q = GLKQuaternionMultiply(cq2, q)
            
            result = SCNVector4(x: -q.y, y: q.x, z: q.z, w: q.w)
            
        case .landscapeLeft:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 0, 1, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            var q = GLKQuaternionMultiply(cq1, aq)
            q = GLKQuaternionMultiply(cq2, q)
            
            result = SCNVector4(x: q.y, y: -q.x, z: q.z, w: q.w)
            
        case .portraitUpsideDown:
            let cq1 = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            let cq2 = GLKQuaternionMakeWithAngleAndAxis(.pi, 0, 0, 1)
            var q = GLKQuaternionMultiply(cq1, aq)
            q = GLKQuaternionMultiply(cq2, q)
            
            result = SCNVector4(x: -q.x, y: -q.y, z: q.z, w: q.w)
            
        case .unknown:
            fallthrough
        case .portrait:
            let cq = GLKQuaternionMakeWithAngleAndAxis(-(.pi/2), 1, 0, 0)
            let q = GLKQuaternionMultiply(cq, aq)
            
            result = SCNVector4(x: q.x, y: q.y, z: q.z, w: q.w)
        }
        return result
    }
}

fileprivate extension UIView {
    func add(view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let views = ["view": view]
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[view]|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: views))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: views))
    }
}

fileprivate extension FloatingPoint {
    func toDegrees() -> Self {
        return self * 180 / .pi
    }
    
    func toRadians() -> Self {
        return self * .pi / 180
    }
}
