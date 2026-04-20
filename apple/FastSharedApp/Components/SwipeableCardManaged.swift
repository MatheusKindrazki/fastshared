import SwiftUI
import FastSharedCore

/// Coordinator that ensures at most one SwipeableCard is revealed at a time.
///
/// SwiftUI's native `.swipeActions` only works inside `List`. Our History uses
/// `LazyVStack` for fine-grained control over card spacing, chips, and the
/// scroll header, so we roll our own swipe-to-reveal. The manager is what
/// gives a list of SwipeableCards the usual UX where swiping a second card
/// auto-closes the first — without it every row would need to poll siblings.
@MainActor
@Observable
public final class SwipeableCardManager {
    /// Identifier of the currently-revealed card, or nil if everything is
    /// closed. Writing `nil` closes any open card (cards observe this).
    public var openCardID: AnyHashable?

    public init() {}

    public func open(_ id: AnyHashable) {
        guard openCardID != id else { return }
        openCardID = id
    }

    public func closeAll() {
        openCardID = nil
    }
}

/// Card wrapper that reveals trailing actions on a leftward swipe, closes on
/// tap-outside, and cooperates with `SwipeableCardManager` so only one row is
/// open at a time. Works inside any container — designed for `LazyVStack`
/// lists where `.swipeActions` is a no-op.
///
/// Usage:
/// ```swift
/// SwipeableCardManaged(id: link.token, manager: manager) {
///     FriendlyLinkCard(link: link, now: now, colorScheme: colorScheme)
/// } actions: {
///     SwipeAction(label: "Share", systemImage: "square.and.arrow.up",
///                 tint: BrandPalette.accentHot) { share(link) }
///     SwipeAction(label: "Revoke", systemImage: "xmark.circle",
///                 tint: BrandPalette.urgencyCritical, isDestructive: true)
///                 { revoke(link) }
/// }
/// ```
public struct SwipeableCardManaged<ID: Hashable, Content: View>: View {
    private let id: ID
    private let manager: SwipeableCardManager
    private let actions: [SwipeAction]
    private let cornerRadius: CGFloat
    private let content: () -> Content

    // Geometry
    @State private var dragOffset: CGFloat = 0
    // Total width of the revealed action strip. Sized against `.onGeometryChange`
    // in the actions stack so tint buttons always fit their labels + 20pt padding.
    @State private var actionsWidth: CGFloat = 0

    /// Whether the currently-applied offset places the card into its open rest
    /// position. Derived from the manager's `openCardID` rather than a local
    /// bool so sibling rows can force-close us.
    private var isOpen: Bool {
        manager.openCardID == AnyHashable(id)
    }

    /// Fraction of the action strip currently revealed. Drives opacity +
    /// horizontal slide of the per-action tiles so actions feel attached to
    /// the card rather than punching in at reveal.
    private var revealFraction: Double {
        guard actionsWidth > 0 else { return 0 }
        let clamped = min(max(-dragOffset, 0), actionsWidth)
        return Double(clamped / actionsWidth)
    }

    public init(
        id: ID,
        manager: SwipeableCardManager,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: @escaping () -> Content,
        @SwipeActionsBuilder actions: () -> [SwipeAction]
    ) {
        self.id = id
        self.manager = manager
        self.cornerRadius = cornerRadius
        self.content = content
        self.actions = actions()
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            // Action strip (beneath the card, revealed as it slides left)
            actionsStrip
                .opacity(revealFraction)
                .allowsHitTesting(isOpen && dragOffset != 0)

            // The card itself
            content()
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .offset(x: dragOffset)
                // WHY: `.simultaneousGesture` (not `.gesture`) so the enclosing
                // ScrollView still receives vertical pan events. With the
                // exclusive `.gesture` SwiftUI routes every drag to us even
                // when clearly vertical — the list froze because our guard
                // `returned` without offsetting, but the scroll was already
                // cancelled. Simultaneous lets both compete; our horizontal
                // bias check decides who wins per-axis.
                .simultaneousGesture(swipeGesture)
                // Tap while open → close (without re-triggering the underlying
                // NavigationLink tap). Tap while closed is ignored so the
                // wrapped content's own tap target (a NavigationLink, usually)
                // keeps working.
                .simultaneousGesture(TapGesture().onEnded {
                    if isOpen { manager.closeAll() }
                })
        }
        .onChange(of: manager.openCardID) { _, newValue in
            // Sibling opened, or external closeAll() — reflect in geometry.
            if newValue != AnyHashable(id) && dragOffset != 0 {
                withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
                    dragOffset = 0
                }
            } else if newValue == AnyHashable(id) && dragOffset == 0 {
                // Something opened us programmatically. Snap to rest.
                withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
                    dragOffset = -actionsWidth
                }
            }
        }
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                // Horizontal bias guard — only react when the translation is
                // dominantly horizontal, otherwise SwiftUI steals the gesture
                // for vertical scrolling.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = isOpen ? -actionsWidth : 0
                var next = base + value.translation.width
                // Clamp: don't allow sliding past the action strip, and cap
                // rightward rubber-banding at +40pt.
                if next < -actionsWidth { next = -actionsWidth + (next + actionsWidth) * 0.25 }
                if next > 0 { next = next * 0.25 }
                dragOffset = next
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    // Vertical gesture — reset to prior rest position.
                    withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
                        dragOffset = isOpen ? -actionsWidth : 0
                    }
                    return
                }

                let projected = dragOffset + value.predictedEndTranslation.width * 0.15
                let threshold = -(actionsWidth * 0.4)
                let shouldOpen = projected < threshold

                withAnimation(.spring(duration: 0.38, bounce: 0.2)) {
                    if shouldOpen {
                        dragOffset = -actionsWidth
                        manager.open(AnyHashable(id))
                    } else {
                        dragOffset = 0
                        if isOpen { manager.closeAll() }
                    }
                }
            }
    }

    // MARK: - Actions strip

    private var actionsStrip: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                SwipeActionButton(action: action) {
                    // Close ourselves after the action fires so the callsite
                    // doesn't have to remember.
                    withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
                        dragOffset = 0
                    }
                    manager.closeAll()
                    action.perform()
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { actionsWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in actionsWidth = newValue }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - SwipeAction model

public struct SwipeAction: Identifiable {
    public let id = UUID()
    public let label: String
    public let systemImage: String
    public let tint: Color
    public let isDestructive: Bool
    public let perform: () -> Void

    public init(
        label: String,
        systemImage: String,
        tint: Color,
        isDestructive: Bool = false,
        perform: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

@resultBuilder
public enum SwipeActionsBuilder {
    public static func buildBlock(_ components: SwipeAction...) -> [SwipeAction] {
        components
    }
}

// MARK: - SwipeActionButton

private struct SwipeActionButton: View {
    let action: SwipeAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(action.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
