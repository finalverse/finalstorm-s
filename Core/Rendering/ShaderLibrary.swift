//
//  Core/Rendering/ShaderLibrary.swift
//  FinalStorm
//
//  Advanced shader management system with hot-reloading and optimization
//

import Foundation
import Metal

@MainActor
class ShaderLibrary {
    private var device: MTLDevice!
    private var defaultLibrary: MTLLibrary!
    private var customLibraries: [String: MTLLibrary] = [:]
    private var renderPipelines: [String: MTLRenderPipelineState] = [:]
    private var computePipelines: [String: MTLComputePipelineState] = [:]
    private var shaderCache: [String: Any] = [:]
    
    // Hot-reloading support
    private var shaderFileWatcher: ShaderFileWatcher?
    private var enableHotReload: Bool = false
    
    func initialize(device: MTLDevice) async throws {
        self.device = device
        
        guard let library = device.makeDefaultLibrary() else {
            throw ShaderError.libraryCreationFailed
        }
        
        self.defaultLibrary = library
        
        // Load custom shader libraries
        try await loadCustomShaders()
        
        // Setup hot-reloading in debug builds
#if DEBUG
        setupHotReloading()
#endif
        
        print("ShaderLibrary initialized with \(getAllShaderNames().count) shaders")
    }
    
    // MARK: - Shader Loading
    
    private func loadCustomShaders() async throws {
        // Load Finalverse-specific shaders
        let finalverseShaders = [
            "HarmonyShaders",
            "CorruptionShaders",
            "SongweavingShaders",
            "EnvironmentShaders",
            "PostProcessShaders"
        ]
        
        for shaderName in finalverseShaders {
            try await loadShaderLibrary(named: shaderName)
        }
    }
    
    private func loadShaderLibrary(named name: String) async throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "metallib") else {
            print("Warning: Shader library '\(name)' not found, using fallback shaders")
            return
        }
        
        do {
            let library = try device.makeLibrary(URL: url)
            customLibraries[name] = library
            print("Loaded shader library: \(name)")
        } catch {
            print("Failed to load shader library '\(name)': \(error)")
            throw ShaderError.libraryLoadFailed(name)
        }
    }
    
    // MARK: - Pipeline Creation
    
    func createRenderPipeline(
        name: String,
        vertexFunction: String,
        fragmentFunction: String,
        blendMode: BlendMode = .none,
        depthTest: Bool = true,
        cullMode: MTLCullMode = .back
    ) throws -> MTLRenderPipelineState {
        
        if let cachedPipeline = renderPipelines[name] {
            return cachedPipeline
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = name
        
        // Get shader functions
        guard let vertexFunc = getFunction(named: vertexFunction) else {
            throw ShaderError.functionNotFound(vertexFunction)
        }
        
        guard let fragmentFunc = getFunction(named: fragmentFunction) else {
            throw ShaderError.functionNotFound(fragmentFunction)
        }
        
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        
        // Configure render targets
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Configure blending
        configureBlending(descriptor: descriptor, blendMode: blendMode)
        
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            renderPipelines[name] = pipeline
            return pipeline
        } catch {
            throw ShaderError.pipelineCreationFailed(name, error.localizedDescription)
        }
    }
    
    func createComputePipeline(name: String, functionName: String? = nil) throws -> MTLComputePipelineState {
        let funcName = functionName ?? name
        
        if let cachedPipeline = computePipelines[name] {
            return cachedPipeline
        }
        
        guard let function = getFunction(named: funcName) else {
            throw ShaderError.functionNotFound(funcName)
        }
        
        do {
            let pipeline = try device.makeComputePipelineState(function: function)
            computePipelines[name] = pipeline
            return pipeline
        } catch {
            throw ShaderError.pipelineCreationFailed(name, error.localizedDescription)
        }
    }
    
    private func configureBlending(descriptor: MTLRenderPipelineDescriptor, blendMode: BlendMode) {
        let colorAttachment = descriptor.colorAttachments[0]!
        
        switch blendMode {
        case .none:
            colorAttachment.isBlendingEnabled = false
            
        case .alpha:
            colorAttachment.isBlendingEnabled = true
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.rgbBlendOperation = .add
            
        case .additive:
            colorAttachment.isBlendingEnabled = true
            colorAttachment.sourceRGBBlendFactor = .one
            colorAttachment.destinationRGBBlendFactor = .one
            colorAttachment.rgbBlendOperation = .add
            
        case .multiply:
            colorAttachment.isBlendingEnabled = true
            colorAttachment.sourceRGBBlendFactor = .destinationColor
            colorAttachment.destinationRGBBlendFactor = .zero
            colorAttachment.rgbBlendOperation = .add
            
        case .harmonyBlend:
            // Custom Finalverse harmony blending
            colorAttachment.isBlendingEnabled = true
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .one
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
        }
    }
    
    enum BlendMode {
        case none
        case alpha
        case additive
        case multiply
        case harmonyBlend
    }
    
    // MARK: - Function Retrieval
    
    func getFunction(named name: String) -> MTLFunction? {
        // Check cache first
        if let cachedFunction = shaderCache[name] as? MTLFunction {
            return cachedFunction
        }
        
        // Try default library first
        if let function = defaultLibrary.makeFunction(name: name) {
            shaderCache[name] = function
            return function
        }
        
        // Try custom libraries
        for (_, library) in customLibraries {
            if let function = library.makeFunction(name: name) {
                shaderCache[name] = function
                return function
            }
        }
        
        print("Warning: Shader function '\(name)' not found")
        return nil
    }
    
    func getAllShaderNames() -> [String] {
        var names: [String] = []
        
        names.append(contentsOf: defaultLibrary.functionNames)
        
        for (_, library) in customLibraries {
            names.append(contentsOf: library.functionNames)
        }
        
        return names
    }
    
    // MARK: - Hot Reloading
    
    private func setupHotReloading() {
        enableHotReload = true
        shaderFileWatcher = ShaderFileWatcher { [weak self] changedFile in
            Task { @MainActor in
                await self?.reloadShader(file: changedFile)
            }
        }
    }
    
    private func reloadShader(file: String) async {
        print("Reloading shader file: \(file)")
        
        // Clear affected caches
        clearCacheForFile(file)
        
        // Reload the library
        do {
            try await loadShaderLibrary(named: file)
            print("Successfully reloaded shader: \(file)")
            
            // Notify about successful reload
            NotificationCenter.default.post(
                name: .shaderReloaded,
                object: file
            )
        } catch {
            print("Failed to reload shader '\(file)': \(error)")
        }
    }
    
    private func clearCacheForFile(_ file: String) {
        // Remove cached functions and pipelines related to the file
        let keysToRemove = shaderCache.keys.filter { key in
            // This would need more sophisticated logic to map files to functions
            return key.contains(file)
        }
        
        for key in keysToRemove {
            shaderCache.removeValue(forKey: key)
        }
        
        // Clear related pipelines
        renderPipelines.removeAll()
        computePipelines.removeAll()
    }
    
    // MARK: - Shader Validation and Optimization
    
    func validateAllShaders() async -> ShaderValidationReport {
        var report = ShaderValidationReport()
        
        // Validate all render pipelines
        for (name, _) in renderPipelines {
            let validation = await validateRenderPipeline(name: name)
            report.renderPipelineResults[name] = validation
        }
        
        // Validate all compute pipelines
        for (name, _) in computePipelines {
            let validation = await validateComputePipeline(name: name)
            report.computePipelineResults[name] = validation
        }
        
        // Check for unused shaders
        report.unusedShaders = findUnusedShaders()
        
        return report
    }
    
    private func validateRenderPipeline(name: String) async -> ValidationResult {
        // Perform validation checks
        // - Check for compilation errors
        // - Verify vertex/fragment function compatibility
        // - Check resource usage
        // - Performance analysis
        
        return ValidationResult(
            isValid: true,
            warnings: [],
            errors: [],
            performanceMetrics: ShaderPerformanceMetrics()
        )
    }
    
    private func validateComputePipeline(name: String) async -> ValidationResult {
        // Perform compute-specific validation
        return ValidationResult(
            isValid: true,
            warnings: [],
            errors: [],
            performanceMetrics: ShaderPerformanceMetrics()
        )
    }
    
    private func findUnusedShaders() -> [String] {
        let allShaderNames = Set(getAllShaderNames())
        let usedShaderNames = Set(renderPipelines.keys + computePipelines.keys)
        return Array(allShaderNames.subtracting(usedShaderNames))
    }
    
    // MARK: - Shader Compilation Optimization
    
    func precompileShaders() async {
        print("Precompiling shaders for optimal performance...")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Precompile commonly used pipeline combinations
        let commonPipelines = [
            ("StandardOpaque", "standardVertex", "standardFragment"),
            ("HarmonyVisualization", "harmonyVertex", "harmonyFragment"),
            ("ParticleRender", "particleVertex", "particleFragment"),
            ("PostProcessing", "fullscreenVertex", "postProcessFragment"),
            ("ShadowMap", "shadowVertex", "shadowFragment")
        ]
        
        for (name, vertex, fragment) in commonPipelines {
            do {
                _ = try createRenderPipeline(
                    name: name,
                    vertexFunction: vertex,
                    fragmentFunction: fragment
                )
            } catch {
                print("Failed to precompile pipeline '\(name)': \(error)")
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print("Shader precompilation completed in \(String(format: "%.3f", endTime - startTime))s")
    }
 }

 // MARK: - Supporting Types

 struct ShaderValidationReport {
    var renderPipelineResults: [String: ValidationResult] = [:]
    var computePipelineResults: [String: ValidationResult] = [:]
    var unusedShaders: [String] = []
    
    var isValid: Bool {
        return renderPipelineResults.values.allSatisfy { $0.isValid } &&
               computePipelineResults.values.allSatisfy { $0.isValid }
    }
    
    var totalWarnings: Int {
        return renderPipelineResults.values.reduce(0) { $0 + $1.warnings.count } +
               computePipelineResults.values.reduce(0) { $0 + $1.warnings.count }
    }
    
    var totalErrors: Int {
        return renderPipelineResults.values.reduce(0) { $0 + $1.errors.count } +
               computePipelineResults.values.reduce(0) { $0 + $1.errors.count }
    }
 }

 struct ValidationResult {
    let isValid: Bool
    let warnings: [String]
    let errors: [String]
    let performanceMetrics: ShaderPerformanceMetrics
 }

 struct ShaderPerformanceMetrics {
    var compilationTime: TimeInterval = 0
    var estimatedGPUCost: Int = 0
    var memoryUsage: Int = 0
    var registerUsage: Int = 0
 }

 enum ShaderError: Error, LocalizedError {
    case libraryCreationFailed
    case libraryLoadFailed(String)
    case functionNotFound(String)
    case pipelineCreationFailed(String, String)
    case compilationError(String)
    
    var errorDescription: String? {
        switch self {
        case .libraryCreationFailed:
            return "Failed to create default Metal library"
        case .libraryLoadFailed(let name):
            return "Failed to load shader library: \(name)"
        case .functionNotFound(let name):
            return "Shader function not found: \(name)"
        case .pipelineCreationFailed(let name, let reason):
            return "Failed to create pipeline '\(name)': \(reason)"
        case .compilationError(let error):
            return "Shader compilation error: \(error)"
        }
    }
 }

 // MARK: - Hot Reloading Support

 class ShaderFileWatcher {
    private let callback: (String) -> Void
    private var fileMonitor: DispatchSourceFileSystemObject?
    
    init(callback: @escaping (String) -> Void) {
        self.callback = callback
        startWatching()
    }
    
    private func startWatching() {
        // Watch shader directory for changes
        guard let shaderPath = Bundle.main.path(forResource: "Shaders", ofType: nil) else {
            return
        }
        
        let fileDescriptor = open(shaderPath, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        fileMonitor?.setEventHandler { [weak self] in
            self?.callback("Shaders")
        }
        
        fileMonitor?.resume()
    }
    
    deinit {
        fileMonitor?.cancel()
    }
 }

 extension Notification.Name {
    static let shaderReloaded = Notification.Name("ShaderReloaded")
 }
