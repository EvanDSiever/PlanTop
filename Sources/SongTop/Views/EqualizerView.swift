import AppKit
import QuartzCore

public final class EqualizerView: NSView {
    private var barLayers: [CALayer] = []
    private var isAnimating: Bool = false
    private let barColor: NSColor
    
    public init(barColor: NSColor = .white, frame: NSRect = NSRect(x: 0, y: 0, width: 22, height: 16)) {
        self.barColor = barColor
        super.init(frame: frame)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        self.barColor = .white
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }
    
    private func setupBars() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()
        
        let barWidth: CGFloat = 3.0
        let spacing: CGFloat = 2.5
        let startX: CGFloat = (bounds.width - (4 * barWidth + 3 * spacing)) / 2.0
        
        for i in 0..<4 {
            let bar = CALayer()
            let x = startX + CGFloat(i) * (barWidth + spacing)
            bar.frame = CGRect(x: x, y: 2, width: barWidth, height: 4)
            bar.backgroundColor = barColor.cgColor
            bar.cornerRadius = 1.5
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }
    
    public func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        
        let heights: [[CGFloat]] = [
            [4, 13, 6, 11, 4],
            [6, 14, 8, 14, 6],
            [5, 9, 13, 7, 5],
            [7, 12, 5, 14, 7]
        ]
        
        for (i, bar) in barLayers.enumerated() {
            let anim = CAKeyframeAnimation(keyPath: "bounds.size.height")
            let pattern = heights[i % heights.count]
            anim.values = pattern
            anim.duration = 0.55 + Double(i) * 0.08
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(anim, forKey: "equalizerBounce")
        }
    }
    
    public func stopAnimating() {
        isAnimating = false
        for bar in barLayers {
            bar.removeAnimation(forKey: "equalizerBounce")
            bar.bounds.size.height = 3
        }
    }
    
    public override func layout() {
        super.layout()
        setupBars()
        if isAnimating {
            isAnimating = false
            startAnimating()
        }
    }
}
