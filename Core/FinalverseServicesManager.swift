//
//  FinalverseServicesManager.swift
//  FinalStorm
//
//  Manages all Finalverse AI services
//

import Foundation
import Combine

@MainActor
class FinalverseServicesManager: ObservableObject {
    let songEngine: SongEngine
    let echoEngine: EchoEngine
    let aiOrchestra: AIOrchestra
    let harmonyService: HarmonyService
    let storyEngine: StoryEngine
    let worldEngineService: WorldEngineService
    let symphonyEngine: SymphonyEngine
    let silenceService: SilenceService
    
    init() {
        self.songEngine = SongEngine()
        self.echoEngine = EchoEngine()
        self.aiOrchestra = AIOrchestra()
        self.harmonyService = HarmonyService()
        self.storyEngine = StoryEngine()
        self.worldEngineService = WorldEngineService()
        self.symphonyEngine = SymphonyEngine()
        self.silenceService = SilenceService()
        
        // Initialize services
        initializeServices()
    }
    
    private func initializeServices() {
        Task {
            await songEngine.initialize()
            await echoEngine.initialize()
            await aiOrchestra.initialize()
            await harmonyService.initialize()
            await storyEngine.initialize()
            await worldEngineService.initialize()
            await symphonyEngine.initialize()
            await silenceService.initialize()
        }
    }
}
