import UIKit

/// Live recording waveform modeled on DSWaveformImage's `WaveformLiveView` + striped
/// `LinearWaveformRenderer` (mirrored about center). Sample convention matches the library:
/// `0` = loud, `1` = silence. Safe to use without the DSWaveformImage package.
final class ChatLiveWaveformView: UIView {

    var stripeWidth: CGFloat = 2
    var stripeSpacing: CGFloat = 2
    var stripeColor: UIColor = .white
    /// Left-pad with silence (`1`) until real samples fill the visible stripe slots.
    var shouldDrawSilencePadding: Bool = true

    private var samples: [Float] = []
    private let dampingPercentage: Float = 0.125

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        samples = []
        setNeedsDisplay()
    }

    /// Append a sample in DSWaveformImage convention (`0...1`, 0 loud / 1 silence).
    func add(sample: Float) {
        let clamped = max(0, min(1, sample))
        samples.append(clamped)
        trimToVisibleCapacity()
        setNeedsDisplay()
    }

    func add(samples newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        samples.append(contentsOf: newSamples.map { max(0, min(1, $0)) })
        trimToVisibleCapacity()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trimToVisibleCapacity()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }

        let slot = stripeWidth + stripeSpacing
        let stripeCount = max(1, Int(floor((bounds.width + stripeSpacing) / slot)))
        var drawSamples = samples

        if shouldDrawSilencePadding, drawSamples.count < stripeCount {
            let pad = Array(repeating: Float(1), count: stripeCount - drawSamples.count)
            drawSamples = pad + drawSamples
        } else if drawSamples.count > stripeCount {
            drawSamples = Array(drawSamples.suffix(stripeCount))
        }

        drawSamples = damp(drawSamples)

        let centerY = bounds.midY
        let halfHeight = bounds.height / 2
        let minAmp = max(1.5, stripeWidth * 0.6)

        context.setStrokeColor(stripeColor.cgColor)
        context.setLineWidth(stripeWidth)
        context.setLineCap(.round)

        for (i, sample) in drawSamples.enumerated() {
            // Library: amp = (1 - sample) * mapping — silence (1) → tiny, loud (0) → tall.
            let inverted = 1 - CGFloat(sample)
            let amp = max(minAmp, inverted * halfHeight * 0.95)
            let x = CGFloat(i) * slot + stripeWidth / 2
            context.move(to: CGPoint(x: x, y: centerY - amp))
            context.addLine(to: CGPoint(x: x, y: centerY + amp))
            context.strokePath()
        }
    }

    private func visibleStripeCapacity() -> Int {
        guard bounds.width > 0 else { return 64 }
        let slot = stripeWidth + stripeSpacing
        return max(1, Int(floor((bounds.width + stripeSpacing) / slot)))
    }

    private func trimToVisibleCapacity() {
        let capacity = visibleStripeCapacity()
        // Keep a little headroom so scroll feels continuous.
        let maxKeep = capacity * 2
        if samples.count > maxKeep {
            samples = Array(samples.suffix(maxKeep))
        }
    }

    /// Soft fade at both ends (DSWaveformImage default damping ~12.5% both sides).
    private func damp(_ values: [Float]) -> [Float] {
        let count = Float(values.count)
        guard count > 4, dampingPercentage > 0 else { return values }
        let pct = dampingPercentage
        return values.enumerated().map { index, value in
            let x = Float(index)
            let factor: Float
            if x < count * pct {
                let t = x / (count * pct)
                factor = t * t * (3 - 2 * t) // smoothstep
            } else if x > (1 - pct) * count {
                let t = (count - x) / (count * pct)
                factor = t * t * (3 - 2 * t)
            } else {
                factor = 1
            }
            // Damping pulls toward silence (1) in DS convention.
            return 1 - ((1 - value) * factor)
        }
    }
}
