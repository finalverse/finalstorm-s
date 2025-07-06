import SwiftUI
import RealityKit

struct ContentView_visionOS: View {
    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceIsShown = false
    @State private var cameraYaw: Float = 0
    @State private var cameraPitch: Float = 0
    @State private var cameraDistance: Float = 6
    
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        VStack {
            Text("Welcome to FinalStorm")
                .font(.title)
            
            Toggle("Show Immersive Space", isOn: $showImmersiveSpace)
                .toggleStyle(.button)
                .padding(.top, 50)
            
            if immersiveSpaceIsShown {
                RealityView { content in
                    let scene = Entity()
                    
                    if let worldEntity = try? await worldManager.createWorldEntity() {
                        scene.addChild(worldEntity)
                    }

                    if let avatarEntity = try? await avatarSystem.createLocalAvatar() {
                        scene.addChild(avatarEntity)
                    }

                    let camera = PerspectiveCamera()
                    camera.position = SIMD3<Float>(0, 2, 6)
                    camera.look(at: SIMD3<Float>(0, 1, 0), from: camera.position, relativeTo: nil)
                    scene.addChild(camera)

                    let reticle = Entity()
                    let reticleMaterial = SimpleMaterial(color: .blue, isMetallic: false)
                    reticle.components.set(ModelComponent(mesh: .generateSphere(radius: 0.05), materials: [reticleMaterial]))
                    scene.addChild(reticle)

                    content.add(scene)
                } update: { content in
                    if let avatar = avatarSystem.currentAvatar,
                       let camera = content.entities.compactMap({ $0 as? PerspectiveCamera }).first {

                        let avatarPos = avatar.position
                        let radius = cameraDistance
                        let offsetX = radius * cos(cameraPitch) * sin(cameraYaw)
                        let offsetY = radius * sin(cameraPitch)
                        let offsetZ = radius * cos(cameraPitch) * cos(cameraYaw)
                        let target = avatarPos + SIMD3<Float>(offsetX, offsetY + 2, offsetZ)
                        let lerpFactor: Float = 0.1
                        camera.position = mix(camera.position, target, t: lerpFactor)
                        camera.look(at: avatarPos, from: camera.position, relativeTo: nil)
                    }
                    avatarSystem.updateAvatar(in: content)

                    if let avatar = avatarSystem.currentAvatar,
                       let reticle = content.entities.first(where: { $0.components[ModelComponent.self] != nil && $0.name == "" }) {
                        let forward = SIMD3<Float>(0, 0, -1)
                        let transform = avatar.transform.matrix
                        let worldForward = (transform * SIMD4<Float>(forward.x, forward.y, forward.z, 0)).xyz
                        let targetPosition = avatar.position + normalize(worldForward) * 2.0
                        reticle.position = targetPosition

                        // Animate pulsing scale
                        let scale = 1.0 + 0.1 * sin(Float(Date().timeIntervalSinceReferenceDate * 2))
                        reticle.scale = SIMD3<Float>(repeating: scale)

                        // Color shift when close
                        let dist = distance(avatar.position, targetPosition)
                        let newColor: UIColor = dist < 1.5 ? .green : .blue
                        if var model = reticle.model {
                            model.materials = [SimpleMaterial(color: newColor, isMetallic: false)]
                            reticle.model = model
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let sensitivity: Float = 0.005
                            cameraYaw += Float(value.translation.width) * sensitivity
                            cameraPitch -= Float(value.translation.height) * sensitivity
                            cameraPitch = max(-.pi / 4, min(.pi / 4, cameraPitch))
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let scale = Float(value)
                            cameraDistance /= scale
                            cameraDistance = min(max(cameraDistance, 2), 12)
                        }
                )
                .gesture(
                    TapGesture()
                        .onEnded {
                            if let avatar = avatarSystem.currentAvatar {
                                // Teleport the avatar forward in the direction it’s facing
                                let forward = SIMD3<Float>(0, 0, -1)
                                let transform = avatar.transform.matrix
                                let forwardWorld = (transform * SIMD4<Float>(forward.x, forward.y, forward.z, 0)).xyz
                                avatar.position += normalize(forwardWorld) * 2.0
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onChange(of: showImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
                    case .opened:
                        immersiveSpaceIsShown = true
                    case .error, .userCancelled:
                        fallthrough
                    @unknown default:
                        immersiveSpaceIsShown = false
                        showImmersiveSpace = false
                    }
                } else if immersiveSpaceIsShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
        }
    }
}
