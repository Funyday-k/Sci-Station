import Foundation

/// Configuration for the force-directed layout algorithm.
public nonisolated struct GraphLayoutConfig: Hashable, Sendable {
    public var repulsion: Double
    public var springLength: Double
    public var springStrength: Double
    public var gravity: Double
    public var damping: Double
    public var maxVelocity: Double
    public var maxIterations: Int
    public var energyThreshold: Double

    public nonisolated init(
        repulsion: Double = 6_000,
        springLength: Double = 80,
        springStrength: Double = 0.05,
        gravity: Double = 0.02,
        damping: Double = 0.85,
        maxVelocity: Double = 12,
        maxIterations: Int = 200,
        energyThreshold: Double = 0.5
    ) {
        self.repulsion = repulsion
        self.springLength = springLength
        self.springStrength = springStrength
        self.gravity = gravity
        self.damping = damping
        self.maxVelocity = maxVelocity
        self.maxIterations = maxIterations
        self.energyThreshold = energyThreshold
    }
}

/// Result of a layout computation.
public nonisolated struct GraphLayoutResult: Sendable {
    public let positions: [String: GraphLayoutPoint]
    public let iterations: Int
    public let finalEnergy: Double
    public let settled: Bool

    public nonisolated init(positions: [String: GraphLayoutPoint], iterations: Int, finalEnergy: Double, settled: Bool) {
        self.positions = positions
        self.iterations = iterations
        self.finalEnergy = finalEnergy
        self.settled = settled
    }
}

/// A 2D point used by the layout engine (avoids importing CoreGraphics in the
/// core target).
public nonisolated struct GraphLayoutPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public nonisolated init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public nonisolated static func + (lhs: GraphLayoutPoint, rhs: GraphLayoutPoint) -> GraphLayoutPoint {
        GraphLayoutPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public nonisolated static func - (lhs: GraphLayoutPoint, rhs: GraphLayoutPoint) -> GraphLayoutPoint {
        GraphLayoutPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public nonisolated static func += (lhs: inout GraphLayoutPoint, rhs: GraphLayoutPoint) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }

    public nonisolated static func -= (lhs: inout GraphLayoutPoint, rhs: GraphLayoutPoint) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }

    public nonisolated func scaled(by factor: Double) -> GraphLayoutPoint {
        GraphLayoutPoint(x: x * factor, y: y * factor)
    }

    public nonisolated var lengthSquared: Double { x * x + y * y }
    public nonisolated var length: Double { (x * x + y * y).squareRoot() }

    public nonisolated func clamped(maxMagnitude: Double) -> GraphLayoutPoint {
        let len = length
        guard len > maxMagnitude else { return self }
        let scale = maxMagnitude / len
        return GraphLayoutPoint(x: x * scale, y: y * scale)
    }

    public nonisolated func clamped(width: Double, height: Double, margin: Double = 20) -> GraphLayoutPoint {
        GraphLayoutPoint(
            x: min(max(x, margin), width - margin),
            y: min(max(y, margin), height - margin)
        )
    }
}

/// Deterministic force-directed graph layout engine using Verlet-style
/// integration. Given the same `seed`, `subgraph`, and `canvasSize`, the
/// output positions are identical across runs.
///
/// Complexity: O(iterations × n²) where n = node count. Acceptable for
/// n ≤ 200 (P46 cap).
public struct GraphLayoutEngine {
    public nonisolated init() {}

    public nonisolated func layout(
        _ subgraph: GraphSubgraph,
        canvasWidth: Double,
        canvasHeight: Double,
        seed: UInt64 = 42,
        config: GraphLayoutConfig = GraphLayoutConfig()
    ) -> GraphLayoutResult {
        let nodeIDs = subgraph.nodes.map(\.id)
        guard !nodeIDs.isEmpty else {
            return GraphLayoutResult(positions: [:], iterations: 0, finalEnergy: 0, settled: true)
        }

        var positions = initialPositions(nodeIDs: nodeIDs, width: canvasWidth, height: canvasHeight, seed: seed)
        var velocities: [String: GraphLayoutPoint] = [:]
        for id in nodeIDs { velocities[id] = GraphLayoutPoint() }

        let edgePairs: [(String, String)] = subgraph.edges.map { ($0.from, $0.to) }
        var finalIteration = 0
        var finalEnergy = 0.0

        for iteration in 0..<config.maxIterations {
            var forces: [String: GraphLayoutPoint] = [:]
            for id in nodeIDs { forces[id] = GraphLayoutPoint() }

            // Repulsion (Coulomb-like) between every pair.
            for i in 0..<nodeIDs.count {
                for j in (i + 1)..<nodeIDs.count {
                    let a = nodeIDs[i]
                    let b = nodeIDs[j]
                    let delta = positions[a]! - positions[b]!
                    let dist = max(delta.length, 0.01)
                    let force = config.repulsion / (dist * dist)
                    let fx = force * (delta.x / dist)
                    let fy = force * (delta.y / dist)
                    forces[a]! += GraphLayoutPoint(x: fx, y: fy)
                    forces[b]! -= GraphLayoutPoint(x: fx, y: fy)
                }
            }

            // Spring forces along edges.
            for (from, to) in edgePairs {
                guard let pa = positions[from], let pb = positions[to] else { continue }
                let delta = pa - pb
                let dist = max(delta.length, 0.01)
                let displacement = dist - config.springLength
                let force = displacement * config.springStrength
                let fx = force * (delta.x / dist)
                let fy = force * (delta.y / dist)
                forces[from]! -= GraphLayoutPoint(x: fx, y: fy)
                forces[to]! += GraphLayoutPoint(x: fx, y: fy)
            }

            // Center gravity.
            let centre = GraphLayoutPoint(x: canvasWidth / 2, y: canvasHeight / 2)
            for id in nodeIDs {
                let toCentre = centre - positions[id]!
                forces[id]! += toCentre.scaled(by: config.gravity)
            }

            // Update velocities and positions.
            var totalEnergy = 0.0
            for id in nodeIDs {
                var velocity = (velocities[id]! + forces[id]!).scaled(by: config.damping)
                velocity = velocity.clamped(maxMagnitude: config.maxVelocity)
                velocities[id] = velocity
                positions[id] = (positions[id]! + velocity).clamped(width: canvasWidth, height: canvasHeight)
                totalEnergy += velocity.lengthSquared
            }

            finalIteration = iteration + 1
            finalEnergy = totalEnergy

            if totalEnergy < config.energyThreshold {
                return GraphLayoutResult(
                    positions: positions,
                    iterations: finalIteration,
                    finalEnergy: finalEnergy,
                    settled: true
                )
            }
        }

        return GraphLayoutResult(
            positions: positions,
            iterations: finalIteration,
            finalEnergy: finalEnergy,
            settled: finalEnergy < config.energyThreshold
        )
    }

    /// Deterministic initial positions based on a seeded PRNG. Nodes are
    /// placed in a circle with jitter so the layout doesn't start from a
    /// degenerate state.
    private nonisolated func initialPositions(
        nodeIDs: [String],
        width: Double,
        height: Double,
        seed: UInt64
    ) -> [String: GraphLayoutPoint] {
        var rng = SeededRNG(seed: seed)
        let cx = width / 2
        let cy = height / 2
        let radius = min(width, height) * 0.35
        var positions: [String: GraphLayoutPoint] = [:]

        for (index, id) in nodeIDs.enumerated() {
            let angle = (Double(index) / Double(max(nodeIDs.count, 1))) * 2 * .pi
            let jitterX = (rng.nextDouble() - 0.5) * 20
            let jitterY = (rng.nextDouble() - 0.5) * 20
            positions[id] = GraphLayoutPoint(
                x: cx + cos(angle) * radius + jitterX,
                y: cy + sin(angle) * radius + jitterY
            )
        }

        return positions
    }
}

/// Simple xorshift64 PRNG for deterministic layout.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextDouble() -> Double {
        Double(next() & 0x1FFFFFFFFFFFFF) / Double(0x1FFFFFFFFFFFFF)
    }
}
