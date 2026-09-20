import AppKit

public struct NeumorphicTheme {
    // MARK: - Surface Plain Colors
    /// Clean, neutral light master background (#F8FAFC)
    public static let masterBackground = NSColor(red: 0.965, green: 0.973, blue: 0.985, alpha: 1.0)
    public static let baseBackground = masterBackground
    public static let panelBackground = masterBackground
    
    /// Plain flat card surface (#FFFFFF)
    public static let cardElevated = NSColor.white
    
    /// Subtle inset / secondary surface
    public static let insetWell = NSColor(red: 0.945, green: 0.955, blue: 0.970, alpha: 1.0)
    
    /// Subtle hairline border highlight
    public static let specularHighlightBorder = NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 0.85)
    
    /// Ambient panel border outline
    public static let panelBorderOutline = NSColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 0.90)
    
    // MARK: - Signature Accents (Vibrant Orange Default + User-Customizable)
    /// Signature Vibrant Orange (#FF700D) default
    public static let defaultOrange = NSColor(red: 1.0, green: 0.44, blue: 0.05, alpha: 1.0)
    
    /// Dynamic user-selected theme accent (Orange by default)
    public static var accentColor: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "plantop_accent_color_hex") ?? UserDefaults.standard.string(forKey: "songtop_accent_color_hex"),
           let color = colorFromHex(hex) {
            return color
        }
        return defaultOrange
    }
    
    public static var accentHairline: NSColor {
        return accentColor.withAlphaComponent(0.85)
    }
    
    // Aliases for unified theme adoption
    public static var coralAccent: NSColor {
        return accentColor
    }
    public static var coralHairline: NSColor {
        return accentHairline
    }
    public static let coralGlow = NSColor(red: 1.0, green: 0.44, blue: 0.05, alpha: 0.20)
    public static let coralPillText = NSColor.white
    
    public static func colorFromHex(_ hex: String) -> NSColor? {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else { return nil }
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    public static func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FF700D" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    // MARK: - Typography (User Customizable)
    public static func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = UserDefaults.standard.string(forKey: "plantop_app_font_family") ?? UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "Rounded"
        if family == "System" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        } else if family == "Monospaced" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        } else if family == "Serif" {
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: desc, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
            }
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }
    
    public static func monospacedRoundedFont(ofSize size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        let family = UserDefaults.standard.string(forKey: "plantop_app_font_family") ?? UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "Rounded"
        if family == "System" || family == "Monospaced" {
            return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }
    
    /// Primary text - Modern slate charcoal (#0F172A)
    public static let textPrimary = NSColor(red: 0.09, green: 0.12, blue: 0.17, alpha: 1.0)
    
    /// Secondary text - Medium cool slate (#64748B)
    public static let textSecondary = NSColor(red: 0.39, green: 0.45, blue: 0.55, alpha: 1.0)
    
    /// Tertiary text - Soft muted slate (#94A3B8)
    public static let textTertiary = NSColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
    
    // MARK: - Shadow Tokens (Plain aesthetic: zero drop shadow artifacts)
    public static let darkSlateShadow = NSColor.clear
    public static let whiteHighlight = NSColor.clear
    public static let slateShadowColor = darkSlateShadow
    public static let whiteHighlightColor = whiteHighlight
    
    // MARK: - Button Tokens
    public static let buttonBackground = NSColor.white
    public static let buttonIconTint = NSColor(red: 0.22, green: 0.28, blue: 0.38, alpha: 1.0)
    public static var buttonActiveBackground: NSColor { return accentColor }
    public static let buttonActiveTint = NSColor.white
    
    // MARK: - Urgency Color Tokens (Clean Plain Aesthetic)
    public static let urgentFill = NSColor.white
    public static var urgentText: NSColor { return accentColor }
    public static var urgentPill: NSColor { return accentColor }
    public static var urgentHairline: NSColor { return accentHairline }
    
    public static let almostUrgentFill = NSColor.white
    public static let almostUrgentText = textPrimary
    public static let almostUrgentPill = insetWell
    public static let almostUrgentHairline = specularHighlightBorder
    
    public static let notUrgentFill = NSColor.white
    public static let notUrgentText = textPrimary
    public static let notUrgentPill = insetWell
    public static let notUrgentHairline = specularHighlightBorder
    
    public static let classNeutralFill = NSColor.white
    public static let classNeutralText = textPrimary
    public static let classNeutralPill = insetWell
    public static let classNeutralHairline = specularHighlightBorder
    
    public static let activeFill = NSColor.white
    public static var activeText: NSColor { return accentColor }
    public static var activePill: NSColor { return accentColor }
    public static var activeHairline: NSColor { return accentHairline }
    
    // MARK: - Futuristic Accents & Typography (User Customizable)
    /// Dynamic vibrant orange / theme accent (#FF700D)
    public static var futuristicOrange: NSColor {
        return accentColor
    }
    
    public static func futuristicTimeFont(ofSize size: CGFloat) -> NSFont {
        let chosenFont = UserDefaults.standard.string(forKey: "plantop_time_font_name") ?? UserDefaults.standard.string(forKey: "songtop_time_font_name") ?? "AlienLeagueCondensed"
        if let font = NSFont(name: chosenFont, size: size) {
            return font
        }
        if let font = NSFont(name: "AlienLeagueCondensed", size: size) {
            return font
        }
        if let font = NSFont(name: "AlienLeague", size: size) {
            return font
        }
        if let font = NSFont(name: "Futura-CondensedLight", size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: .ultraLight)
    }
    
    // MARK: - Plain Text Shadows (Completely zeroed for razor-sharp typography)
    public static var elevatedTextShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.clear
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 0.0
        return shadow
    }
    
    public static var softTextShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.clear
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 0.0
        return shadow
    }
    
    // MARK: - Plain Flat Button Styling
    public static func applyButtonShadow(to layer: CALayer?, cornerRadius: CGFloat = 10, isActive: Bool = false) {
        guard let layer = layer else { return }
        layer.cornerRadius = cornerRadius
        layer.backgroundColor = isActive ? buttonActiveBackground.cgColor : buttonBackground.cgColor
        layer.shadowColor = NSColor.clear.cgColor
        layer.shadowOpacity = 0.0
        layer.shadowRadius = 0.0
        layer.shadowOffset = .zero
        layer.borderColor = isActive ? coralHairline.cgColor : specularHighlightBorder.cgColor
        layer.borderWidth = 0.5
    }
}

// MARK: - Plain Card View (Clean GPU Layer-Backed, Zero CPU Software Rasterization)
open class NeumorphicDepressedCardView: NSView {
    open override var isFlipped: Bool { return true }
    
    public var cornerRadiusValue: CGFloat = 12 {
        didSet { updateAppearance() }
    }
    
    public var surfaceColor: NSColor = NSColor.white {
        didSet { updateAppearance() }
    }
    
    public var innerDarkShadowColor: NSColor = .clear
    public var innerLightHighlightColor: NSColor = .clear
    
    public var outlineColor: NSColor = NeumorphicTheme.specularHighlightBorder {
        didSet { updateAppearance() }
    }
    
    public var outlineWidth: CGFloat = 0.5 {
        didSet { updateAppearance() }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        updateAppearance()
    }
    
    public func updateAppearance() {
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = surfaceColor.cgColor
        layer?.borderColor = outlineColor.cgColor
        layer?.borderWidth = outlineWidth
    }
}

// MARK: - Plain Elevated Card View (Clean Flat Container)
open class NeumorphicElevatedCardView: NSView {
    open override var isFlipped: Bool { return true }
    public let darkShadowLayer = CALayer()
    public let lightShadowLayer = CALayer()
    public let bodySurfaceLayer = CALayer()
    
    public var cornerRadiusValue: CGFloat = 10 {
        didSet { updateAppearance() }
    }
    
    public var surfaceColor: NSColor = NSColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0) {
        didSet { updateAppearance() }
    }
    
    public var outlineColor: NSColor = NeumorphicTheme.specularHighlightBorder {
        didSet { updateAppearance() }
    }
    
    public var outlineWidth: CGFloat = 0.5 {
        didSet { updateAppearance() }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        darkShadowLayer.shadowOpacity = 0.0
        lightShadowLayer.shadowOpacity = 0.0
        bodySurfaceLayer.masksToBounds = true
        
        layer?.addSublayer(darkShadowLayer)
        layer?.addSublayer(lightShadowLayer)
        layer?.addSublayer(bodySurfaceLayer)
        
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        darkShadowLayer.frame = b
        lightShadowLayer.frame = b
        bodySurfaceLayer.frame = b
        CATransaction.commit()
        updateAppearance()
    }
    
    public func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = surfaceColor.cgColor
        layer?.borderColor = outlineColor.cgColor
        layer?.borderWidth = outlineWidth
        
        bodySurfaceLayer.cornerRadius = cornerRadiusValue
        bodySurfaceLayer.backgroundColor = surfaceColor.cgColor
        bodySurfaceLayer.borderWidth = outlineWidth
        bodySurfaceLayer.borderColor = outlineColor.cgColor
        CATransaction.commit()
    }
}

// MARK: - Plain Panel Container View (Clean Modern Window Surface)
open class NeumorphicPanelContainerView: NSView {
    public let darkShadowLayer = CALayer()
    public let lightShadowLayer = CALayer()
    public let contentView = NSView()
    
    public var cornerRadiusValue: CGFloat = 24 {
        didSet { updateAppearance() }
    }
    
    public var panelBackgroundColor: NSColor = NeumorphicTheme.panelBackground {
        didSet { updateAppearance() }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Subtle ambient shadow
        darkShadowLayer.masksToBounds = false
        darkShadowLayer.shadowColor = NSColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.10).cgColor
        darkShadowLayer.shadowRadius = 8.0
        darkShadowLayer.shadowOpacity = 0.50
        darkShadowLayer.shadowOffset = CGSize(width: 0, height: -2.0)
        layer?.addSublayer(darkShadowLayer)
        
        lightShadowLayer.shadowOpacity = 0.0
        layer?.addSublayer(lightShadowLayer)
        
        // Clipped Content Container
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(contentView)
        
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        let b = bounds
        contentView.frame = b
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        darkShadowLayer.frame = b
        let path = CGPath(roundedRect: b, cornerWidth: cornerRadiusValue, cornerHeight: cornerRadiusValue, transform: nil)
        darkShadowLayer.shadowPath = path
        CATransaction.commit()
    }
    
    public func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        darkShadowLayer.cornerRadius = cornerRadiusValue
        darkShadowLayer.backgroundColor = panelBackgroundColor.cgColor
        
        contentView.layer?.cornerRadius = cornerRadiusValue
        contentView.layer?.backgroundColor = panelBackgroundColor.cgColor
        contentView.layer?.borderColor = NeumorphicTheme.panelBorderOutline.cgColor
        contentView.layer?.borderWidth = 0.75
        
        CATransaction.commit()
    }
}

// MARK: - Plain Sunken Well View (Flat Inset Container)
open class NeumorphicSunkenWellView: NSView {
    open override var isFlipped: Bool { return true }
    
    public var cornerRadiusValue: CGFloat = 10 {
        didSet { updateAppearance() }
    }
    
    public var wellColor: NSColor = NeumorphicTheme.insetWell {
        didSet { updateAppearance() }
    }
    
    public var innerDarkShadowColor: NSColor = .clear
    public var innerLightHighlightColor: NSColor = .clear
    public var innerRimColor: NSColor = NeumorphicTheme.specularHighlightBorder
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        updateAppearance()
    }
    
    public func updateAppearance() {
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = wellColor.cgColor
        layer?.borderColor = innerRimColor.cgColor
        layer?.borderWidth = 0.5
    }
}

// MARK: - Plain Dynamic Interactive Button (Instant GPU Color Feedback, No Software Shadows)
open class NeumorphicDynamicButton: NSButton {
    open override var isFlipped: Bool { return true }
    
    public var cornerRadiusValue: CGFloat = 10 {
        didSet {
            layer?.cornerRadius = cornerRadiusValue
            updateAppearance()
        }
    }
    
    public var isPressedDown: Bool = false {
        didSet { updateAppearance() }
    }
    
    public var unpressedBackgroundColor: NSColor = NSColor.white {
        didSet { updateAppearance() }
    }
    
    public var pressedBackgroundColor: NSColor = NeumorphicTheme.baseBackground {
        didSet { updateAppearance() }
    }
    
    public var activeAccentColor: NSColor? = nil {
        didSet { updateAppearance() }
    }
    
    public var innerDarkShadowColor: NSColor = .clear
    public var innerLightHighlightColor: NSColor = .clear
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonSetup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }
    
    private func commonSetup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        layer?.masksToBounds = true
        updateAppearance()
    }
    
    open override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }
    
    public var effectivePressed: Bool {
        return isPressedDown || isHighlighted
    }
    
    public func updateAppearance() {
        guard let l = layer else { return }
        l.cornerRadius = cornerRadiusValue
        l.shadowOpacity = 0.0
        
        if effectivePressed {
            let bg = activeAccentColor ?? pressedBackgroundColor
            l.backgroundColor = bg.cgColor
            l.borderWidth = 0.0
            l.borderColor = NSColor.clear.cgColor
        } else {
            l.backgroundColor = unpressedBackgroundColor.cgColor
            l.borderWidth = 0.5
            l.borderColor = NeumorphicTheme.specularHighlightBorder.cgColor
        }
    }
    
    open override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
