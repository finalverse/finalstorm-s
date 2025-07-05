//
//  InventoryView.swift
//  FinalStorm
//
//  Inventory management interface
//

import SwiftUI

struct InventoryView: View {
    @State private var selectedTab = 0
    @State private var selectedItem: InventoryItem?
    @State private var inventoryItems: [InventoryItem] = InventoryItem.sampleItems
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inventory")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
            
            // Tab bar
            Picker("Category", selection: $selectedTab) {
                Text("All").tag(0)
                Text("Equipment").tag(1)
                Text("Consumables").tag(2)
                Text("Materials").tag(3)
                Text("Quest").tag(4)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(filteredItems) { item in
                        InventorySlot(item: item, isSelected: selectedItem?.id == item.id)
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
                .padding()
            }
            
            // Selected item details
            if let selected = selectedItem {
                ItemDetailView(item: selected)
                    .padding()
                    .background(Color.gray.opacity(0.2))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
        .cornerRadius(20)
    }
    
    private var filteredItems: [InventoryItem] {
        switch selectedTab {
        case 1:
            return inventoryItems.filter { $0.category == .equipment }
        case 2:
            return inventoryItems.filter { $0.category == .consumable }
        case 3:
            return inventoryItems.filter { $0.category == .material }
        case 4:
            return inventoryItems.filter { $0.category == .quest }
        default:
            return inventoryItems
        }
    }
}

struct InventorySlot: View {
    let item: InventoryItem
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                )
            
            VStack {
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundColor(item.rarity.color)
                
                if item.quantity > 1 {
                    Text("\(item.quantity)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                }
            }
            .padding(8)
        }
        .frame(width: 60, height: 60)
    }
}

struct ItemDetailView: View {
    let item: InventoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.icon)
                    .font(.title)
                    .foregroundColor(item.rarity.color)
                
                VStack(alignment: .leading) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(item.rarity.color)
                    
                    Text(item.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if item.quantity > 1 {
                    Text("x\(item.quantity)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(item.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !item.stats.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(item.stats, id: \.0) { stat in
                        HStack {
                            Text(stat.0)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(stat.1)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            
            HStack {
                Button("Use") {
                    // Use item
                }
                .disabled(!item.isUsable)
                
                Button("Drop") {
                    // Drop item
                }
                
                Spacer()
            }
            .padding(.top)
        }
    }
}
