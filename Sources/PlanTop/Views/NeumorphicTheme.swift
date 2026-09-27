import AppKit

// MARK: - Apple (HIG-inspired) Design System
/// Implements the Apple Human Interface Guidelines design system:
/// - Semantic, adaptive system colors (systemBlue, label, secondaryLabel, systemBackground, etc.)
/// - Single system family (SF Pro) with dynamic type scale and 17pt body legibility floor
/// - 8pt grid layout convention with 44pt minimum tap targets
/// - Translucent Liquid Glass materials that float above and defer to content
public struct AppleTheme {
    // MARK: - Colors (Adaptive Semantic Roles)
    
    /// Default Apple Vibrant Electric Yellow (#FFD60A approximate)
    public static let defaultYellow = NSColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1.0)
    
    /// Default Apple systemBlue (#007AFF approximate)
    public static let defaultBlue = NSColor.systemBlue
    
    /// Primary Accent Color: defaultYellow by default, user-customizable
    public static var primary: NSColor {
        if let hex = UserDefaults.standard.string(forKey: "plantop_accent_color_hex") ?? UserDefaults.standard.string(forKey: "songtop_accent_color_hex"),
           let color = colorFromHex(hex) {
            return color
        }
        return defaultYellow
    }
    
    /// Text role: Pure bright white (#FFFFFF) for highest legibility on black islands
    public static var label: NSColor {
        return NSColor.white
    }
    
    /// Secondary label: Crisp silver (#B8B8B8)
    public static var secondaryLabel: NSColor {
        return NSColor(white: 0.72, alpha: 1.0)
    }
    
    /// Tertiary label: Muted gray (#7A7A7A)
    public static var tertiaryLabel: NSColor {
        return NSColor(white: 0.48, alpha: 1.0)
    }
    
    /// Quaternary label: Faint placeholder text
    public static var quaternaryLabel: NSColor {
        return NSColor(white: 0.28, alpha: 1.0)
    }
    
    /// Main background role: True pitch black
    public static var systemBackground: NSColor {
        return NSColor.black
    }
    
    /// Secondary container surface background
    public static var secondarySystemBackground: NSColor {
        return NSColor(white: 0.08, alpha: 1.0)
    }
    
    /// Tertiary grouping background
    public static var tertiarySystemBackground: NSColor {
        return NSColor(white: 0.12, alpha: 1.0)
    }
    
    /// Hairline separator role
    public static var separator: NSColor {
        return NSColor(white: 1.0, alpha: 0.14)
    }
    
    /// Success semantic color (~#34C759 approximate)
    public static var success: NSColor {
        return NSColor.systemGreen
    }
    
    /// Danger semantic color (~#FF3B30 approximate)
    public static var danger: NSColor {
        return NSColor.systemRed
    }
    
    /// Pure pitch black card surface (#000000 true OLED)
    public static var cardBackground: NSColor {
        return NSColor.black
    }
    
    /// Inset well surface inside black card
    public static var insetWell: NSColor {
        return NSColor(white: 0.06, alpha: 1.0)
    }
    
    /// Crisp specular hairline rim for black islands (0.5pt white @ 16%)
    public static var cardBorder: NSColor {
        return NSColor(white: 1.0, alpha: 0.16)
    }
    
    // MARK: - Typography (SF Pro & SF Mono)
    // Scale: large_title: 34, title1: 28, title2: 22, title3: 20, headline: 17, body: 17, callout: 16, subhead: 15, footnote: 13, caption1: 12, caption2: 11
    
    public static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let family = UserDefaults.standard.string(forKey: "plantop_app_font_family") ?? UserDefaults.standard.string(forKey: "songtop_app_font_family") ?? "System"
        switch family {
        case "Rounded":
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: desc, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "Monospaced", "Mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case "Avenir":
            let avenirName: String
            switch weight {
            case .bold, .heavy, .black:
                avenirName = "Avenir-Heavy"
            case .medium, .semibold:
                avenirName = "Avenir-Medium"
            case .light, .ultraLight, .thin:
                avenirName = "Avenir-Light"
            default:
                avenirName = "Avenir-Book"
            }
            return NSFont(name: avenirName, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        case "Serif":
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: desc, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        default:
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
    }
    
    public static func monospacedFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    
    public static func monospacedDigitFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
    
    /// Dedicated dynamic font resolver for lockscreen and island clock
    public static func timeFont(size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        let chosen = UserDefaults.standard.string(forKey: "plantop_time_font_name") ??
                     UserDefaults.standard.string(forKey: "songtop_time_font_name") ?? "SFPro"
        switch chosen {
        case "SFPro", "MonospacedDigit":
            return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        case "SFProRounded", "Rounded":
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded),
               let f = NSFont(descriptor: desc, size: size) {
                return f
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "SFProRegular":
            return NSFont.systemFont(ofSize: size, weight: .regular)
        case "SFMono", "Mono", "Monospaced":
            if let desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.monospaced),
               let f = NSFont(descriptor: desc, size: size) {
                return f
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case "Futura-CondensedLight", "Futura":
            if let f = NSFont(name: "Futura-CondensedMedium", size: size) ??
                       NSFont(name: "Futura-Medium", size: size) ??
                       NSFont(name: "Futura-Bold", size: size) ??
                       NSFont(name: "Futura", size: size) {
                return f
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "AlienLeagueCondensed", "Alien":
            if let f = NSFont(name: "AlienLeagueCondensed", size: size) ??
                       NSFont(name: "AlienLeague", size: size) {
                return f
            }
            return NSFont.systemFont(ofSize: size, weight: weight)
        default:
            if let f = NSFont(name: chosen, size: size) {
                return f
            }
            return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }
    
    // Apple Type Scale Accessors
    public static var largeTitleFont: NSFont { font(size: 34, weight: .regular) }
    public static var title1Font: NSFont     { font(size: 28, weight: .regular) }
    public static var title2Font: NSFont     { font(size: 22, weight: .bold) }
    public static var title3Font: NSFont     { font(size: 20, weight: .semibold) }
    public static var headlineFont: NSFont   { font(size: 17, weight: .semibold) }
    public static var bodyFont: NSFont       { font(size: 17, weight: .regular) } // 17pt legibility floor
    public static var calloutFont: NSFont    { font(size: 16, weight: .regular) }
    public static var subheadFont: NSFont    { font(size: 15, weight: .regular) }
    public static var footnoteFont: NSFont   { font(size: 13, weight: .regular) }
    public static var caption1Font: NSFont   { font(size: 12, weight: .regular) }
    public static var caption2Font: NSFont   { font(size: 11, weight: .regular) }
    
    // MARK: - Layout & Spacing
    /// 8pt grid convention with 4pt subdivisions
    public static let spacingConvention: CGFloat = 8.0
    public static let minTapTarget: CGFloat = 44.0
    public static let cornerRadius: CGFloat = 14.0
    public static let cornerRadiusLarge: CGFloat = 20.0
    public static let cornerRadiusMedium: CGFloat = 10.0
    public static let cornerRadiusSmall: CGFloat = 8.0
    
    public static let grid4: CGFloat = 4.0
    public static let grid8: CGFloat = 8.0
    public static let grid12: CGFloat = 12.0
    public static let grid16: CGFloat = 16.0
    public static let grid20: CGFloat = 20.0
    public static let grid24: CGFloat = 24.0
    public static let grid32: CGFloat = 32.0
    
    // MARK: - Utilities
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
        let rgbColor: NSColor
        if let converted = color.usingColorSpace(.sRGB) {
            rgbColor = converted
        } else if let converted = color.usingColorSpace(.deviceRGB) {
            rgbColor = converted
        } else {
            return "#007AFF"
        }
        let r = max(0, min(255, Int(round(rgbColor.redComponent * 255))))
        let g = max(0, min(255, Int(round(rgbColor.greenComponent * 255))))
        let b = max(0, min(255, Int(round(rgbColor.blueComponent * 255))))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - NeumorphicTheme (Compatibility Adapter for Existing Callers & Unit Tests)
public struct NeumorphicTheme {
    // MARK: - Surface Plain Colors
    public static var masterBackground: NSColor { return AppleTheme.systemBackground }
    public static var baseBackground: NSColor { return AppleTheme.systemBackground }
    public static var panelBackground: NSColor { return AppleTheme.systemBackground }
    
    /// Flat card surface
    public static var cardElevated: NSColor { return AppleTheme.cardBackground }
    
    /// Subtle inset / secondary surface
    public static var insetWell: NSColor { return AppleTheme.insetWell }
    
    /// Hairline border highlight
    public static var specularHighlightBorder: NSColor { return AppleTheme.cardBorder }
    
    /// Ambient panel border outline
    public static var panelBorderOutline: NSColor { return AppleTheme.cardBorder }
    
    // MARK: - Primary Accent
    public static var accentColor: NSColor {
        return AppleTheme.primary
    }
    
    public static var accentHairline: NSColor {
        return accentColor.withAlphaComponent(0.85)
    }
    
    public static var coralAccent: NSColor {
        return accentColor
    }
    public static var coralHairline: NSColor {
        return accentHairline
    }
    public static var coralGlow: NSColor {
        return accentColor.withAlphaComponent(0.20)
    }
    public static let coralPillText = NSColor.white
    
    public static func colorFromHex(_ hex: String) -> NSColor? {
        return AppleTheme.colorFromHex(hex)
    }
    
    public static func hexString(from color: NSColor) -> String {
        return AppleTheme.hexString(from: color)
    }
    
    // MARK: - Typography
    /// Backward-compatible Avenir resolver (retained for explicit test expectations)
    public static func avenirFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let fontName: String
        switch weight {
        case .ultraLight, .thin, .light:
            fontName = "Avenir-Light"
        case .medium:
            fontName = "Avenir-Medium"
        case .semibold, .bold:
            fontName = "Avenir-Heavy"
        case .heavy, .black:
            fontName = "Avenir-Black"
        default:
            fontName = "Avenir-Book"
        }
        if let f = NSFont(name: fontName, size: size) {
            return f
        }
        if let f = NSFont(name: "Avenir", size: size) {
            return f
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
    
    public static func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return AppleTheme.font(size: size, weight: weight)
    }
    
    public static func monospacedRoundedFont(ofSize size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        return AppleTheme.monospacedDigitFont(size: size, weight: weight)
    }
    
    /// Dedicated font for live timers and clocks
    public static func timerFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        return futuristicTimeFont(ofSize: size)
    }
    
    /// Semantic Primary text (adapts automatically in dark and light modes)
    public static var textPrimary: NSColor { return AppleTheme.label }
    
    /// Semantic Secondary text
    public static var textSecondary: NSColor { return AppleTheme.secondaryLabel }
    
    /// Semantic Tertiary text
    public static var textTertiary: NSColor { return AppleTheme.tertiaryLabel }
    
    // MARK: - Button Tokens
    public static var buttonBackground: NSColor { return AppleTheme.cardBackground }
    public static var buttonIconTint: NSColor { return AppleTheme.secondaryLabel }
    public static var buttonActiveBackground: NSColor { return accentColor }
    public static let buttonActiveTint = NSColor.white
    
    // MARK: - Urgency Color Tokens
    public static var urgentFill: NSColor { return AppleTheme.cardBackground }
    public static var urgentText: NSColor { return accentColor }
    public static var urgentPill: NSColor { return accentColor }
    public static var urgentHairline: NSColor { return accentHairline }
    
    public static var almostUrgentFill: NSColor { return AppleTheme.cardBackground }
    public static var almostUrgentText: NSColor { return textPrimary }
    public static var almostUrgentPill: NSColor { return insetWell }
    public static var almostUrgentHairline: NSColor { return specularHighlightBorder }
    
    public static var notUrgentFill: NSColor { return AppleTheme.cardBackground }
    public static var notUrgentText: NSColor { return textPrimary }
    public static var notUrgentPill: NSColor { return insetWell }
    public static var notUrgentHairline: NSColor { return specularHighlightBorder }
    
    public static var classNeutralFill: NSColor { return AppleTheme.cardBackground }
    public static var classNeutralText: NSColor { return textPrimary }
    public static var classNeutralPill: NSColor { return insetWell }
    public static var classNeutralHairline: NSColor { return specularHighlightBorder }
    
    public static var activeFill: NSColor { return AppleTheme.cardBackground }
    public static var activeText: NSColor { return accentColor }
    public static var activePill: NSColor { return accentColor }
    public static var activeHairline: NSColor { return accentHairline }
    
    public static var futuristicOrange: NSColor {
        return accentColor
    }
    
    public static func futuristicTimeFont(ofSize size: CGFloat) -> NSFont {
        return AppleTheme.timeFont(size: size, weight: .bold)
    }
}

// MARK: - Liquid Glass Translucent Card View (Floating Island)
open class NeumorphicDepressedCardView: NSView {
    open override var isFlipped: Bool { return true }
    
    public let visualEffectView = NSVisualEffectView()
    private var trackingArea: NSTrackingArea?
    public var isMouseHovered: Bool = false
    
    public var cornerRadiusValue: CGFloat = 14 {
        didSet { updateAppearance() }
    }
    
    public var surfaceColor: NSColor = AppleTheme.cardBackground {
        didSet { updateAppearance() }
    }
    
    public var innerDarkShadowColor: NSColor = .clear
    public var innerLightHighlightColor: NSColor = .clear
    
    public var outlineColor: NSColor = AppleTheme.cardBorder {
        didSet { updateAppearance() }
    }
    
    public var outlineWidth: CGFloat = 0.5 {
        didSet { updateAppearance() }
    }
    
    public var showsAmbientShadow: Bool = true {
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
        layer?.masksToBounds = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.masksToBounds = true
        addSubview(visualEffectView, positioned: .below, relativeTo: nil)
        
        updateAppearance()
    }
    
    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }
    
    open override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isMouseHovered = true
        updateAppearance()
    }
    
    open override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isMouseHovered = false
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        visualEffectView.frame = b
        updateAppearance()
    }
    
    public func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Delicate Apple Ambient Drop Shadow for Floating Island effect
        if showsAmbientShadow {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isMouseHovered ? 0.35 : 0.22
            layer?.shadowRadius = isMouseHovered ? 12.0 : 8.0
            layer?.shadowOffset = CGSize(width: 0, height: isMouseHovered ? -4 : -2.5)
        } else {
            layer?.shadowOpacity = 0.0
        }
        
        // Pure Pitch Black Island Surface & Specular Hairline
        visualEffectView.state = surfaceColor.alphaComponent < 1.0 ? .active : .inactive
        visualEffectView.layer?.cornerRadius = cornerRadiusValue
        visualEffectView.layer?.borderColor = outlineColor.cgColor
        visualEffectView.layer?.borderWidth = outlineWidth
        
        CATransaction.commit()
    }
    
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - Plain Elevated Card View (Translucent Glass Container)
open class NeumorphicElevatedCardView: NSView {
    open override var isFlipped: Bool { return true }
    public let darkShadowLayer = CALayer()
    public let lightShadowLayer = CALayer()
    public let bodySurfaceLayer = CALayer()
    
    public var cornerRadiusValue: CGFloat = 12 {
        didSet { updateAppearance() }
    }
    
    public var surfaceColor: NSColor = AppleTheme.cardBackground {
        didSet { updateAppearance() }
    }
    
    public var outlineColor: NSColor = AppleTheme.cardBorder {
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
    
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

open class FlippedNeumorphicView: NSView {
    open override var isFlipped: Bool { return true }
}

// MARK: - Transparent Panel Container View (Floating Islands Host)
/// Transparent container coordinating the floating island constellation
open class NeumorphicPanelContainerView: NSView {
    open override var isFlipped: Bool { return true }
    
    public let visualEffectView = NSVisualEffectView()
    public let contentView: NSView = FlippedNeumorphicView()
    
    public var cornerRadiusValue: CGFloat = 20 {
        didSet { updateAppearance() }
    }
    
    public var isBackgroundVisible: Bool = false {
        didSet { updateAppearance() }
    }
    
    public var panelBackgroundColor: NSColor = .clear {
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
        
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.isHidden = !isBackgroundVisible
        addSubview(visualEffectView)
        
        // Flipped Content Host
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false
        addSubview(contentView)
        
        updateAppearance()
    }
    
    open override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        visualEffectView.frame = b
        contentView.frame = b
    }
    
    public func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        layer?.cornerRadius = cornerRadiusValue
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0.0
        
        visualEffectView.isHidden = !isBackgroundVisible
        visualEffectView.layer?.cornerRadius = cornerRadiusValue
        visualEffectView.layer?.borderColor = isBackgroundVisible ? AppleTheme.cardBorder.cgColor : NSColor.clear.cgColor
        visualEffectView.layer?.borderWidth = isBackgroundVisible ? 0.5 : 0.0
        
        contentView.layer?.cornerRadius = cornerRadiusValue
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.borderWidth = 0
        
        CATransaction.commit()
    }
    
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - Sunken Well View (Flat Inset Container)
open class NeumorphicSunkenWellView: NSView {
    open override var isFlipped: Bool { return true }
    
    public var cornerRadiusValue: CGFloat = 10 {
        didSet { updateAppearance() }
    }
    
    public var wellColor: NSColor = AppleTheme.insetWell {
        didSet { updateAppearance() }
    }
    
    public var innerRimColor: NSColor = AppleTheme.cardBorder
    
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
    
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - Dynamic Interactive Button (Apple HIG Tap Target & Feedback)
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
    
    public var unpressedBackgroundColor: NSColor = AppleTheme.cardBackground {
        didSet { updateAppearance() }
    }
    
    public var pressedBackgroundColor: NSColor = AppleTheme.primary {
        didSet { updateAppearance() }
    }
    
    public var activeAccentColor: NSColor? = nil {
        didSet { updateAppearance() }
    }
    
    public var unpressedBorderColor: NSColor = AppleTheme.cardBorder {
        didSet { updateAppearance() }
    }
    
    public var unpressedBorderWidth: CGFloat = 0.5 {
        didSet { updateAppearance() }
    }
    
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
            l.borderWidth = unpressedBorderWidth
            l.borderColor = unpressedBorderColor.cgColor
        }
    }
    
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
    
    open override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
