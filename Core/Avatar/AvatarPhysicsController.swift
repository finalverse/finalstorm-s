import RealityKit

class AvatarPhysicsController {
    func setupPhysics(for avatar: Entity) {
        // Placeholder physics logic
        let shape = ShapeResource.generateCapsule(height: 1.8, radius: 0.4)
        avatar.components.set(CollisionComponent(shapes: [shape]))
        avatar.components.set(PhysicsBodyComponent(massProperties: .default,
                                                   material: .default,
                                                   mode: .kinematic))
    }
}
