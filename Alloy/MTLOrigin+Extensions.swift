//
//  MTLOrigin+Extensions.swift
//  AIBeauty
//
//  Created by Andrey Volodin on 03.10.2018.
//

import Metal

public extension MTLOrigin {
    static let zero = MTLOrigin(x: 0, y: 0, z: 0)
    
    func clamped(to size: MTLSize) -> MTLOrigin {
        return MTLOrigin(x: min(max(self.x, 0), size.width),
                         y: min(max(self.y, 0), size.height),
                         z: min(max(self.z, 0), size.depth))
    }
}
