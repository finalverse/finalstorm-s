import RealityKit

class AvatarInventoryManager {
    func canAddItem(_ item: Entity) -> Bool {
        return true // Stub: accept all items
    }

    func addItem(_ item: Entity) {
        print("Item added to inventory: \(item.name)")
    }
}
