//
//  MiniMapView.swift
//  FinalStorm
//
//  Minimap component for navigation
//

import SwiftUI

struct MiniMapView: View {
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var avatarSystem: AvatarSystem
    
    var body: some View {
        ZStack {
            // Map background
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
            
            // Grid overlay
            GeometryReader { geometry in
                Path { path in
                    let gridSize = 10
                    let cellWidth = geometry.size.width / CGFloat(gridSize)
                    let cellHeight = geometry.size.height / CGFloat(gridSize)
                    
                    // Vertical lines
                    for i in 1..<gridSize {
                        path.move(to: CGPoint(x: CGFloat(i) * cellWidth, y: 0))
                        path.addLine(to: CGPoint(x: CGFloat(i) * cellWidth, y: geometry.size.height))
                    }
                    
                    // Horizontal lines
                    for i in 1..<gridSize {
                        path.move(to: CGPoint(x: 0, y: CGFloat(i) * cellHeight))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: CGFloat(i) * cellHeight))
                    }
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                
                // Player position
                if let avatar = avatarSystem.localAvatar {
                    let mapPosition = worldToMapPosition(
                        worldPos: avatar.position,
                        mapSize: geometry.size
                    )
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .position(mapPosition)
                    
                    // Direction indicator
                    Path { path in
                        path.move(to: mapPosition)
                        let forward = CGPoint(
                            x: mapPosition.x + 10,
                            y: mapPosition.y
                        )
                        path.addLine(to: forward)
                    }
                    .stroke(Color.green, lineWidth: 2)
                }
                
                // Other entities
                ForEach(Array(worldManager.visibleEntities), id: \.id) { entity in
                    if entity !== avatarSystem.localAvatar {
                        let mapPos = worldToMapPosition(
                            worldPos: entity.position,
                            mapSize: geometry.size
                        )
                        
                        Circle()
                            .fill(entityColor(for: entity))
                            .frame(width: 4, height: 4)
                            .position(mapPos)
                    }
                }
            }
            .padding(10)
            
            // Compass
            VStack {
                HStack {
                    Spacer()
                    Text("N")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(5)
                }
                Spacer()
            }
        }
    }
    
    private func worldToMapPosition(worldPos: SIMD3<Float>, mapSize: CGSize) -> CGPoint {
        // Convert world coordinates to map coordinates
        let mapX = CGFloat(worldPos.x + 128) / 256 * mapSize.width
        let mapY = CGFloat(worldPos.z + 128) / 256 * mapSize.height
        
        return CGPoint(x: mapX, y: mapY)
    }
    
    private func entityColor(for entity: Entity) -> Color {
        if entity is EchoEntity {
            return .yellow
        } else if entity is AvatarEntity {
            return .blue
        } else {
            return .gray
        }
    }
}
