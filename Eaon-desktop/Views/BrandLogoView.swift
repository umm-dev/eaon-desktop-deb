import SwiftUI

struct BrandLogoView: View {
    let brand: ProviderBrand
    var size: CGFloat = 20
    /// Aqua Chat is dark-first; always use dark-mode logo assets.
    var logoColorScheme: ColorScheme = .dark
    /// A user-picked image for a custom (BYOK) provider connection — takes
    /// over rendering entirely when set, since `brand` there is really just
    /// "closest wire-format match," not necessarily the real company.
    var customImage: NSImage? = nil

    var body: some View {
        Group {
            if let customImage {
                Image(nsImage: customImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if brand == .aqua {
                // Aqua's real mark already exists natively in this codebase
                // (it's the app's own brand geometry) — render it directly
                // rather than round-tripping through a rasterized/vector
                // asset file that would just be a copy of this same shape.
                AquaMark(size: size)
            } else if let asset = brand.logoAssetName(for: logoColorScheme),
               let nsImage = BrandLogoLoader.image(named: asset) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                Image(systemName: brand.fallbackIcon)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(brand.accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A brand's logo in a soft, brand-tinted circular chip — the provider-row
/// visual unit used in Settings' Model Providers list and its detail pages.
/// A soft tint (not a fully-saturated fill) so every brand reads clearly
/// regardless of its own accent color — a solid fill would render invisibly
/// for a brand like xAI, whose defined accent is white.
struct ProviderBadge: View {
    let brand: ProviderBrand
    var size: CGFloat = 30
    /// See `BrandLogoView.customImage` — when set, fills the whole badge
    /// (a real logo image carries its own visual weight) rather than
    /// sitting small and centered the way a catalog icon mark does.
    var customImage: NSImage? = nil
    @Environment(\.themeColors) private var colors

    var body: some View {
        Circle()
            .fill(brand.accentColor.opacity(0.16))
            .overlay(Circle().stroke(colors.borderSubtle, lineWidth: 1))
            .frame(width: size, height: size)
            .overlay {
                BrandLogoView(brand: brand, size: customImage == nil ? size * 0.6 : size, customImage: customImage)
            }
    }
}
