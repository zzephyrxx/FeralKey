// SPDX-License-Identifier: GPL-3.0-or-later
// Native material design inspired by deeplethe/solid-glass (MIT).
import SwiftUI

enum GlassTheme: String, CaseIterable, Identifiable {
    case daylight, graphite
    var id: String { rawValue }
    var isDark: Bool { self == .graphite }
    var title: String { isDark ? "深灰" : "明亮" }
    var symbol: String { isDark ? "moon" : "sun.max" }
    var scheme: ColorScheme { isDark ? .dark : .light }
    var background: Color { isDark ? Color(white: 0.145) : Color(red: 0.905, green: 0.915, blue: 0.93) }
    var foreground: Color { isDark ? Color(white: 0.94) : Color(white: 0.13) }
    var secondary: Color { isDark ? Color(white: 0.68) : Color(red: 0.36, green: 0.38, blue: 0.41) }
    var muted: Color { isDark ? Color(white: 0.52) : Color(white: 0.46) }
    var accent: Color { isDark ? Color(red: 0.78, green: 0.85, blue: 0.83) : Color(red: 0.23, green: 0.34, blue: 0.31) }
    var edge: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.09) }
    var rim: Color { .white.opacity(isDark ? 0.25 : 0.95) }
    var wash: Color { isDark ? Color(white: 0.27).opacity(0.45) : .white.opacity(0.42) }
    var keyFill: Color { isDark ? .white.opacity(0.045) : .white.opacity(0.53) }
    var warning: Color { isDark ? Color(red: 0.88, green: 0.68, blue: 0.40) : Color(red: 0.54, green: 0.34, blue: 0.13) }
}

struct GlassBackdrop: View {
    let theme: GlassTheme
    var body: some View {
        ZStack {
            theme.background
            // Gradual illumination, without decorative shapes behind text.
            if !theme.isDark {
                RadialGradient(colors: [.white.opacity(0.5), .clear], center: .topLeading, startRadius: 0, endRadius: 950)
                RadialGradient(colors: [Color(red: 0.62, green: 0.72, blue: 0.74).opacity(0.09), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct GlassSelection: View {
    let theme: GlassTheme
    var radius: CGFloat = 12
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.keyFill)
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.clear).liquidControl(theme, radius: radius)
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(LinearGradient(colors: [theme.rim.opacity(0.7), theme.edge], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
        .shadow(color: .black.opacity(theme.isDark ? 0.09 : 0.045), radius: 3, x: 0, y: 1.5)
    }
}

struct GlassPane: ViewModifier {
    let theme: GlassTheme
    var radius: CGFloat = 20
    var raised = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.wash)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.edge, lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 0.7)
                    .strokeBorder(LinearGradient(colors: [theme.rim, .white.opacity(theme.isDark ? 0.015 : 0.12), .clear, .black.opacity(theme.isDark ? 0.20 : 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.16 : 0.055), radius: raised ? 20 : 12, x: 0, y: raised ? 10 : 5)
            .shadow(color: .black.opacity(theme.isDark ? 0.10 : 0.025), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func glassPane(_ theme: GlassTheme, radius: CGFloat = 20, raised: Bool = false) -> some View {
        modifier(GlassPane(theme: theme, radius: radius, raised: raised))
    }

    @ViewBuilder func liquidControl(_ theme: GlassTheme, radius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(theme.isDark ? .white.opacity(0.035) : .white.opacity(0.12)).interactive(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            glassPane(theme, radius: radius)
        }
    }
}

struct FeralButtonStyle: ButtonStyle {
    let theme: GlassTheme
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let textColor: Color = prominent ? (theme.isDark ? Color(white: 0.16) : .white) : theme.foreground
        let fill: Color = prominent ? theme.foreground : theme.keyFill
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(prominent ? 0.30 : (theme.isDark ? 0.20 : 0.9)), theme.edge], startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
            }
            .foregroundStyle(textColor)
            .shadow(color: .black.opacity(prominent ? 0.12 : 0.035), radius: 3, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.38)
    }
}

// A full-width settings row: the icon, title, empty space and chevron all
// activate the same button. Content controls remain separate hit targets.
private final class FeralDisclosureState: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
}

struct FeralDisclosure<Content:View>: View {
    let title:String
    let theme:GlassTheme
    let symbol:String
    let content:Content
    @StateObject private var state = FeralDisclosureState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title:String,theme:GlassTheme,symbol:String = "slider.horizontal.3",@ViewBuilder content:()->Content) {
        self.title = title; self.theme = theme; self.symbol = symbol; self.content = content()
    }
    var body:some View {
        VStack(spacing:0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) { state.expanded.toggle() }
            } label: {
                HStack(spacing:12) {
                    Image(systemName:symbol).font(.system(size:13,weight:.medium))
                        .frame(width:30,height:30).background(theme.foreground.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
                    Text(title).font(.system(size:13,weight:.medium))
                    Spacer(minLength:16)
                    Text(state.expanded ? "收起" : "展开").font(.system(size:11)).foregroundStyle(theme.secondary)
                    Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold))
                        .rotationEffect(.degrees(state.expanded ? 90 : 0)).frame(width:18,height:24).foregroundStyle(theme.secondary)
                }.foregroundStyle(theme.foreground).padding(.horizontal,14).frame(maxWidth:.infinity,minHeight:54)
                    .background(theme.foreground.opacity(state.hovering ? 0.055 : 0.015))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).onHover { state.hovering = $0 }
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(Text(title)).accessibilityValue(state.expanded ? "已展开" : "已折叠")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("点击整行以展开或收起设置")
            if state.expanded {
                Divider().overlay(theme.edge).padding(.horizontal,14)
                content.frame(maxWidth:.infinity,alignment:.leading).padding(14)
                    .transition(.opacity)
            }
        }.background(theme.keyFill.opacity(0.65),in:RoundedRectangle(cornerRadius:13,style:.continuous))
            .clipShape(RoundedRectangle(cornerRadius:13,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:13,style:.continuous).strokeBorder(theme.edge,lineWidth:0.7).allowsHitTesting(false))
    }
}
