//
//  ContentView.swift
//  Terrain
//
//  Created by Matthew Waller on 5/21/24.
//

import SwiftUI
import RealityKit

struct ContentView : View {
    var body: some View {
        ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: true)

        let anchor = AnchorEntity(world: .init(-2, -3, -32))
        
        let terrain = RBTerrain()
        
        let generator = RBPerlinNoiseGenerator(seed: nil)
        terrain.formula = {(x: Int32, y: Int32) in
            return generator.valueFor(x: x, y: y)
        }
        
        terrain.create(withImage: UIImage(named: "grid")!)
//        terrain.create(withColor: .orange)
        anchor.children.append(terrain)
        
        // Add the horizontal plane anchor to the scene
        arView.scene.anchors.append(anchor)
        terrain.generateCollisionShapes(recursive: true)
        arView.installGestures([.all], for: terrain)
        return arView
        
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

#Preview {
    ContentView()
}

import Foundation
import RealityKit
import UIKit
import simd

typealias RBTerrainFormula = ((Int32, Int32) -> (Double))

class RBTerrain: Entity, HasModel, HasCollision {
    private var _heightScale = 256
    private var _terrainWidth = 32
    private var _terrainLength = 32
    private var _texture: UIImage?
    private var _color = UIColor.white
    
    var formula: RBTerrainFormula?
    
    var length: Int {
        return _terrainLength
    }
    
    var width: Int {
        return _terrainWidth
    }
    
    var texture: UIImage? {
        get {
            return _texture
        }
        set(value) {
            _texture = value
            updateMaterial()
        }
    }
    
    var color: UIColor {
        get {
            return _color
        }
        set(value) {
            _color = value
            updateMaterial()
        }
    }
    
    func valueFor(x: Int32, y: Int32) -> Double {
        return formula?(x, y) ?? 0.0
    }
    
    private func updateMaterial() {
        guard let modelEntity = self.children.first as? ModelEntity else { return }
        
        if let texture = _texture?.cgImage {
            var material = SimpleMaterial()
            
            let textureMade: TextureResource = try! .generate(from: texture, options: .init(semantic: nil))
            let baseColor = MaterialParameters.Texture(textureMade)

            material.color = .init(tint: .white, texture: baseColor)
            modelEntity.model?.materials = [material]
        } else {
            let material = UnlitMaterial.init(color: _color)
            modelEntity.model?.materials = [material]
            self.children[0] = modelEntity
        }
    }
    
    private func createGeometry() -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        let w = Float(_terrainWidth)
        let h = Float(_terrainLength)
        let scale = Float(_heightScale)
        
        for y in 0..<Int(h) {
            for x in 0..<Int(w) {
                let topLeftZ = Float(valueFor(x: Int32(x), y: Int32(y + 1))) / scale
                let topRightZ = Float(valueFor(x: Int32(x + 1), y: Int32(y + 1))) / scale
                let bottomLeftZ = Float(valueFor(x: Int32(x), y: Int32(y))) / scale
                let bottomRightZ = Float(valueFor(x: Int32(x + 1), y: Int32(y))) / scale
                
                let topLeft = SIMD3<Float>(Float(x), topLeftZ, Float(y + 1))
                let topRight = SIMD3<Float>(Float(x + 1), topRightZ, Float(y + 1))
                let bottomLeft = SIMD3<Float>(Float(x), bottomLeftZ, Float(y))
                let bottomRight = SIMD3<Float>(Float(x + 1), bottomRightZ, Float(y))
                
                vertices.append(contentsOf: [bottomLeft, topLeft, topRight, bottomRight])
                
                let index = UInt32(vertices.count)
                indices.append(contentsOf: [index - 4, index - 3, index - 2, index - 4, index - 2, index - 1])
            }
        }
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(vertices)
        meshDescriptor.primitives = .triangles(indices)
        
        return try! MeshResource.generate(from: [meshDescriptor])
    }
    
    func create(withImage image: UIImage?) {
        let geometry = createGeometry()
        let modelEntity = ModelEntity(mesh: geometry)
        self.addChild(modelEntity)
        
        if let image = image {
            self.texture = image
        } else {
            self.color = UIColor.green
        }
    }
    
    func create(withColor color: UIColor) {
        let geometry = createGeometry()
        let modelEntity = ModelEntity(mesh: geometry)
        self.addChild(modelEntity)
        
        self.color = color
    }
    
    init(width: Int, length: Int, scale: Int) {
        super.init()
        
        _terrainWidth = width
        _terrainLength = length
        _heightScale = scale
    }
    
    required init() {
        super.init()
    }
}

//
//  RBPerlinNoiseGenerator.swift
//  Perlin noise generator (used for terrain class)
//
//  Created by Roger Boesch on 12/07/16.
//  Based on Obj-C code created by Steven Troughton-Smith on 24/12/11.
//

import UIKit

class RBPerlinNoiseGenerator {
    private static let noiseX = 1619
    private static let noiseY = 31337
    private static let noiseSeed = 1013
    
    private var _seed: Int = 1
    
    // -------------------------------------------------------------------------

    private func interpolate(a: Double, b: Double, x: Double) ->Double {
        let ft: Double = x * Double.pi
        let f: Double = (1.0-cos(ft)) * 0.5
        
        return a*(1.0-f)+b*f
    }

    // -------------------------------------------------------------------------

    private func findNoise(x: Double, y: Double) ->Double {
        var n = (RBPerlinNoiseGenerator.noiseX*Int(x) +
                 RBPerlinNoiseGenerator.noiseY*Int(y) +
                 RBPerlinNoiseGenerator.noiseSeed * _seed) & 0x7fffffff
        
        n = (n >> 13) ^ n
        n = (n &* (n &* n &* 60493 + 19990303) + 1376312589) & 0x7fffffff
        
        return 1.0 - Double(n)/1073741824
    }

    // -------------------------------------------------------------------------

    private func noise(x: Double, y: Double) ->Double {
        let floorX: Double = Double(Int(x))
        let floorY: Double = Double(Int(y))
        
        let s = findNoise(x:floorX, y:floorY)
        let t = findNoise(x:floorX+1, y:floorY)
        let u = findNoise(x:floorX, y:floorY+1)
        let v = findNoise(x:floorX+1, y:floorY+1)
        
        let i1 = interpolate(a:s, b:t, x:x-floorX)
        let i2 = interpolate(a:u, b:v, x:x-floorX)
        
        return interpolate(a:i1, b:i2, x:y-floorY)
    }
 
    // -------------------------------------------------------------------------
    // MARK: - Calculate a noise value for x,y

    func valueFor(x: Int32, y: Int32) ->Double {
        let octaves = 2
        let p: Double = 1/2
        let zoom: Double = 6
        var getnoise: Double = 0
        
        for a in 0..<octaves-1 {
            let frequency = pow(2, Double(a))
            let amplitude = pow(p, Double(a))
            
            getnoise += noise(x:(Double(x))*frequency/zoom, y:(Double(y))/zoom*frequency)*amplitude
        }
        
        var value: Double = Double(((getnoise*128.0)+128.0))
        
        if (value > 255) {
            value = 255
        }
        else if (value < 0) {
            value = 0
        }
        
        return value
    }

    // -------------------------------------------------------------------------
    // MARK: - Initialisation

    init(seed: Int? = nil) {
        if (seed == nil) {
            _seed = Int(arc4random()) % Int(INT32_MAX)
        }
        else {
            _seed = seed!
        }
    }

    // -------------------------------------------------------------------------

}
