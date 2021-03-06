//
//  AlloyTests.swift
//  AlloyTests
//
//  Created by Andrey Volodin on 20/01/2019.
//  Copyright © 2019 avolodin. All rights reserved.
//

import XCTest
import Alloy

class AlloyTests: XCTestCase {

    var context: MTLContext! = nil

    var evenInitState: MTLComputePipelineState! = nil
    var evenOptimizedInitState: MTLComputePipelineState! = nil
    var exactInitState: MTLComputePipelineState! = nil

    var evenProcessState: MTLComputePipelineState! = nil
    var evenOptimizedProcessState: MTLComputePipelineState! = nil
    var exactProcessState: MTLComputePipelineState! = nil

    var textureBaseWidth = 1024
    var textureBaseHeight = 1024
    var gpuIterations = 4

    override func setUp() {
        self.context = MTLContext(device: Metal.device)

        guard let library = self.context.shaderLibrary(for: AlloyTests.self) ?? self.context.standardLibrary else {
            fatalError("Could not load shader library")
        }

        self.evenInitState = try! library.computePipelineState(function: "initialize_even")

        let computeStateDescriptor = MTLComputePipelineDescriptor()
        computeStateDescriptor.computeFunction = library.makeFunction(name: "initialize_even")!
        computeStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        self.evenOptimizedInitState = try! self.context
                                               .device
                                               .makeComputePipelineState(descriptor: computeStateDescriptor,
                                                                         options: [],
                                                                         reflection: nil)

        self.exactInitState = try! library.computePipelineState(function: "initialize_exact")

        self.evenProcessState = try! library.computePipelineState(function: "process_even")

        let processComputeStateDescriptor = MTLComputePipelineDescriptor()
        processComputeStateDescriptor.computeFunction = library.makeFunction(name: "process_even")!
        processComputeStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        self.evenOptimizedProcessState = try! self.context
            .device
            .makeComputePipelineState(descriptor: processComputeStateDescriptor,
                                      options: [],
                                      reflection: nil)

        self.exactProcessState = try! library.computePipelineState(function: "process_exact")
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEvenPerformance() {
        self.measure {
            self.runGPUWork { (encoder, texture, outputTexture) in
                encoder.setTexture(texture, index: 0)
                encoder.dispatch2d(state: self.evenInitState, covering: texture.size)

                encoder.setTexture(outputTexture, index: 1)
                encoder.dispatch2d(state: self.evenProcessState, covering: texture.size)
            }
        }
    }

    func testEvenOptimizedPerformance() {
        self.measure {
            self.runGPUWork { (encoder, texture, outputTexture) in
                encoder.setTexture(texture, index: 0)
                encoder.dispatch2d(state: self.evenOptimizedInitState, covering: texture.size)

                encoder.setTexture(outputTexture, index: 1)
                encoder.dispatch2d(state: self.evenOptimizedProcessState, covering: texture.size)
            }
        }
    }

    func testExactPerformance() {
        self.measure {
            self.runGPUWork { (encoder, texture, outputTexture) in
                encoder.setTexture(texture, index: 0)
                encoder.dispatch2d(state: self.exactInitState, exactly: texture.size)

                encoder.setTexture(outputTexture, index: 1)
                encoder.dispatch2d(state: self.exactProcessState, exactly: texture.size)
            }
        }
    }

    func runGPUWork(encoding: (MTLComputeCommandEncoder, MTLTexture, MTLTexture) -> Void) {
        let maximumThreadgroupSize = evenInitState.max2dThreadgroupSize

        var totalGPUTime: CFTimeInterval = 0
        var iterations = 0

        for wd in 0..<maximumThreadgroupSize.width {
            for ht in 0..<maximumThreadgroupSize.height {
                var texture = self.context.texture(width:  self.textureBaseWidth + wd,
                                                   height: self.textureBaseHeight + ht,
                                                   pixelFormat: .rgba8Unorm)!

                var outputTexture = self.context.texture(width:  self.textureBaseWidth + wd,
                                                         height: self.textureBaseHeight + ht,
                                                         pixelFormat: .rgba8Unorm)!

                self.context.scheduleAndWait { buffer in
                    buffer.compute { encoder in
                        for _ in 0...self.gpuIterations {
                            encoding(encoder, texture, outputTexture)

                            swap(&texture, &outputTexture)
                        }
                    }

                    buffer.addCompletedHandler { buffer in
                        if #available(iOS 10.3, tvOS 10.3, *) {
                            iterations += 1
                            totalGPUTime += buffer.gpuExecutionTime
                        }
                    }
                }
            }
        }

        print("\(#function) average GPU Time: \(totalGPUTime / CFTimeInterval(iterations))")
    }
}

class IdealSizeTests: XCTestCase {
    var context: MTLContext!

    var evenState: MTLComputePipelineState! = nil
    var evenOptimizedState: MTLComputePipelineState! = nil
    var exactState: MTLComputePipelineState! = nil

    var textureBaseMultiplier = 16
    var gpuIterations = 256

    override func setUp() {
        self.context = MTLContext(device: Metal.device)

        guard let library = self.context.shaderLibrary(for: IdealSizeTests.self) ?? self.context.standardLibrary else {
            fatalError("Could not load shader library")
        }

        self.evenState = try! library.computePipelineState(function: "fill_with_threadgroup_size_even")

        let computeStateDescriptor = MTLComputePipelineDescriptor()
        computeStateDescriptor.computeFunction = library.makeFunction(name: "fill_with_threadgroup_size_even")!
        computeStateDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true

        self.evenOptimizedState = try! self.context
            .device
            .makeComputePipelineState(descriptor: computeStateDescriptor,
                                      options: [],
                                      reflection: nil)

        self.exactState = try! library.computePipelineState(function: "fill_with_threadgroup_size_exact")
    }

    func testSpeedOnIdealSize() {
        var bestTimeCounter: [String: Int] = [:]

        for _ in 1...self.gpuIterations {
            let size = self.evenState.max2dThreadgroupSize
            let texture = self.context.texture(width: size.width * self.textureBaseMultiplier,
                                               height: size.height * self.textureBaseMultiplier,
                                               pixelFormat: .rg16Uint,
                                               usage: .shaderWrite)!

            var results = [(String, CFTimeInterval)]()

            self.context.scheduleAndWait { buffer in
                buffer.compute { encoder in
                    encoder.setTexture(texture, index: 0)
                    encoder.dispatch2d(state: self.evenState, covering: texture.size)
                }

                buffer.addCompletedHandler({ buffer in
                    results.append(("Even", buffer.gpuExecutionTime))
                })
            }

            self.context.scheduleAndWait { buffer in
                buffer.compute { encoder in
                    encoder.setTexture(texture, index: 0)
                    encoder.dispatch2d(state: self.evenOptimizedState, covering: texture.size)
                }

                buffer.addCompletedHandler({ buffer in
                    results.append(("Even optimized", buffer.gpuExecutionTime))
                })
            }

            self.context.scheduleAndWait { buffer in
                buffer.compute { encoder in
                    encoder.setTexture(texture, index: 0)
                    encoder.dispatch2d(state: self.exactState, exactly: texture.size)
                }

                buffer.addCompletedHandler({ buffer in
                    results.append(("Exact", buffer.gpuExecutionTime))
                })
            }

            results.sort { $0.1 < $1.1 }
            bestTimeCounter[results.first!.0, default: 0] += 1
        }

        print(bestTimeCounter)
    }

}
