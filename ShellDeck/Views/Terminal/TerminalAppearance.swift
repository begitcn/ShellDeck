import AppKit
import SwiftTerm

enum TerminalAppearance {
    static func apply(to terminal: TerminalView) {
        terminal.configureNativeColors()

        if let font = preferredTerminalFont(size: terminal.font.pointSize) {
            terminal.font = font
        }
    }

    private static func preferredTerminalFont(size: CGFloat) -> NSFont? {
        let pointSize = size > 0 ? size : 13

        for name in preferredFontNames {
            if let font = NSFont(name: name, size: pointSize) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }

    private static let preferredFontNames = [
        "JetBrainsMonoNFM-Regular",
        "JetBrainsMonoNF-Regular",
        "JetBrainsMonoNLNFM-Regular",
        "SauceCodeProNFM",
        "SauceCodeProNF",
        "MesloLGS-NF-Regular",
        "MesloLGM-NF-Regular",
        "HackNerdFont-Regular",
        "FiraCodeNerdFont-Regular",
        "CaskaydiaCoveNerdFontMono-Regular",
        "CaskaydiaMonoNerdFontMono-Regular"
    ]
}
