import UIKit
import QuartzCore

/// Renders the visible swipe path as the user drags their finger.
/// Trail is split into time-based chunks (~100ms each) that individually
/// fade out over ~1s, creating a smooth comet-tail effect.
class SwipeTrailLayer: CALayer {

    // MARK: - Chunk model

    private struct TrailChunk {
        let layer: CAShapeLayer
        let startTime: TimeInterval
        var points: [CGPoint]
    }

    // MARK: - Configuration

    /// How long each chunk takes to fully fade out (seconds)
    private let fadeDuration: TimeInterval = 1.0
    /// How often to start a new chunk (seconds)
    private let chunkInterval: TimeInterval = 0.100

    // MARK: - State

    private var chunks: [TrailChunk] = []
    private var displayLink: CADisplayLink?
    private var isSwiping = false

    // Cached theme values applied to each new chunk sublayer
    private var chunkStrokeColor: CGColor?
    private var chunkLineWidth: CGFloat = 2.5
    private var chunkShadowColor: CGColor?
    private var chunkShadowRadius: CGFloat = 6
    private var chunkShadowOpacity: Float = 0.7

    // MARK: - Init

    override init() {
        super.init()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    // MARK: - Theme

    func applyTheme() {
        let theme = KeyboardTheme.current
        chunkStrokeColor = theme.trailColor.withAlphaComponent(0.8).cgColor
        chunkLineWidth = theme.trailLineWidth
        chunkShadowColor = theme.trailColor.cgColor
        chunkShadowRadius = theme.trailGlowRadius
        chunkShadowOpacity = theme.trailGlowOpacity

        // Update any existing chunk sublayers to match new theme
        for chunk in chunks {
            configureChunkLayer(chunk.layer)
        }
    }

    // MARK: - Public API

    func beginTrail(at point: CGPoint) {
        guard KeyboardTheme.current.trailEnabled else { return }
        // Clear any leftover chunks from a previous swipe
        clearTrail()

        isSwiping = true
        let now = CACurrentMediaTime()
        let chunkLayer = makeChunkLayer()
        addSublayer(chunkLayer)
        chunks.append(TrailChunk(layer: chunkLayer, startTime: now, points: [point]))

        startDisplayLink()
    }

    func addPoint(_ point: CGPoint) {
        guard isSwiping, !chunks.isEmpty else { return }
        let now = CACurrentMediaTime()

        // Check if current chunk is old enough to finalize and start a new one
        let currentChunk = chunks[chunks.count - 1]
        if now - currentChunk.startTime >= chunkInterval {
            finalizeChunkPath(at: chunks.count - 1)

            // New chunk's first point = last point of previous chunk (no visual gap)
            let bridgePoint = currentChunk.points.last ?? point
            let chunkLayer = makeChunkLayer()
            addSublayer(chunkLayer)
            chunks.append(TrailChunk(layer: chunkLayer, startTime: now, points: [bridgePoint, point]))
        } else {
            chunks[chunks.count - 1].points.append(point)
        }

        // Keep the active (last) chunk's rendered path up to date
        updateActiveChunkPath()
    }

    /// Called when the finger lifts. Stops adding points but lets
    /// existing chunks continue fading out naturally via the display link.
    func endTrail() {
        guard isSwiping else { return }
        isSwiping = false

        // Finalize the last chunk's path so it renders correctly while fading
        if !chunks.isEmpty {
            finalizeChunkPath(at: chunks.count - 1)
        }
        // Display link keeps running — tick() will remove chunks as they fade
        // and stop the link once everything is gone.
    }

    /// Hard reset — removes all chunks immediately.
    /// Used for edge cases (theme change, keyboard dismissal, etc.)
    func clearTrail() {
        isSwiping = false
        for chunk in chunks {
            chunk.layer.removeFromSuperlayer()
        }
        chunks.removeAll()
        stopDisplayLink()
    }

    override func removeFromSuperlayer() {
        stopDisplayLink()
        super.removeFromSuperlayer()
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        // NOTE: CADisplayLink retains its target, creating a temporary retain
        // cycle (self → displayLink → self). This is self-resolving: the link
        // is invalidated once all chunks fade, or on clearTrail/removeFromSuperlayer.
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        var indicesToRemove: [Int] = []

        for (i, chunk) in chunks.enumerated() {
            let age = now - chunk.startTime
            let opacity = Float(max(0, 1.0 - age / fadeDuration))
            chunk.layer.opacity = opacity

            if opacity <= 0 {
                chunk.layer.removeFromSuperlayer()
                indicesToRemove.append(i)
            }
        }

        // Remove expired chunks (backwards to preserve indices)
        for i in indicesToRemove.reversed() {
            chunks.remove(at: i)
        }

        // All chunks gone — stop ticking
        if chunks.isEmpty {
            stopDisplayLink()
        }
    }

    // MARK: - Chunk helpers

    private func makeChunkLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        configureChunkLayer(layer)
        return layer
    }

    private func configureChunkLayer(_ layer: CAShapeLayer) {
        layer.fillColor = nil
        layer.strokeColor = chunkStrokeColor
        layer.lineWidth = chunkLineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.shadowColor = chunkShadowColor
        layer.shadowRadius = chunkShadowRadius
        layer.shadowOpacity = chunkShadowOpacity
        layer.shadowOffset = .zero
    }

    /// Build a CGPath from a chunk's points and freeze it on the layer.
    private func finalizeChunkPath(at index: Int) {
        let points = chunks[index].points
        chunks[index].layer.path = buildPath(from: points)
    }

    /// Update the currently-active (last) chunk's path as new points arrive.
    private func updateActiveChunkPath() {
        guard let last = chunks.last else { return }
        last.layer.path = buildPath(from: last.points)
    }

    private func buildPath(from points: [CGPoint]) -> CGPath? {
        guard points.count >= 2 else { return nil }
        let bezier = UIBezierPath()
        bezier.move(to: points[0])
        for p in points.dropFirst() {
            bezier.addLine(to: p)
        }
        return bezier.cgPath
    }
}
