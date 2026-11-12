import SwiftUI

// Shared look: frosted "glass" cards and pills, white focus capsules.
// Dimensions are in tvOS points (the screen is always 1920 x 1080).

extension View {
    /// Frosted glass card: material blur, a white tint, and a soft top-lit edge.
    func glass(_ radius: CGFloat) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.14))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5)
            )
    }
}

/// Round glass button used in the player's tool row. `focused` is driven by Wick's own
/// remote handling, not by the system focus engine.
struct GlassCircleButton: View {
    let systemName: String
    let focused: Bool
    var size: CGFloat = 66

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(focused ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(.ultraThinMaterial))
            .background(Circle().fill(focused ? Color.white : Color.white.opacity(0.18)))
            .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 0 : 0.25), lineWidth: 1.5))
            .scaleEffect(focused ? 1.14 : 1)
            .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 10, y: 6)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// Text pill (Info / Details).
struct GlassPill: View {
    let title: String
    let focused: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 29, weight: .medium))
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 30)
            .frame(height: 64)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.18)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(focused ? 0 : 0.25), lineWidth: 1.5))
            .scaleEffect(focused ? 1.1 : 1)
            .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 10, y: 6)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}

/// A button style that adds no effect of its own, so the label can draw its own focus look.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
