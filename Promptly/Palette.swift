import AppKit

// MARK: - Mattmode Mono palette

enum Palette {
    static let panelBG     = NSColor(red: 0x0f/255, green: 0x0f/255, blue: 0x14/255, alpha: 1)
    static let primary     = NSColor(red: 0xe2/255, green: 0xe8/255, blue: 0xf0/255, alpha: 1)
    static let secondary   = NSColor(red: 0x94/255, green: 0xa3/255, blue: 0xb8/255, alpha: 1)
    static let footer      = NSColor(red: 0x64/255, green: 0x74/255, blue: 0x8b/255, alpha: 1)
    static let matched     = NSColor.white
    static let selFill     = NSColor(white: 0.9, alpha: 0.10)
    static let selBar      = NSColor(white: 0.9, alpha: 0.55)
    static let separator   = NSColor(white: 1.0, alpha: 0.15)

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func monoMedium(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Medium", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }
}
