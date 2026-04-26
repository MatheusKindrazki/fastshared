import SwiftUI
import FastSharedCore

struct AppStoreScreenshotHostView: View {
    let scene: AppStoreScreenshotScene
    let useScrollView: Bool

    init(scene: AppStoreScreenshotScene, useScrollView: Bool = true) {
        self.scene = scene
        self.useScrollView = useScrollView
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            let horizontalPadding = compact ? CGFloat(26) : CGFloat(64)
            let verticalPadding = compact ? CGFloat(34) : CGFloat(54)

            ZStack {
                AppStoreScreenshotBackground()

                if useScrollView {
                    ScrollView(.vertical, showsIndicators: false) {
                        screenshotContent(
                            compact: compact,
                            horizontalPadding: horizontalPadding,
                            verticalPadding: verticalPadding,
                            viewportHeight: proxy.size.height
                        )
                    }
                } else {
                    screenshotContent(
                        compact: compact,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        viewportHeight: proxy.size.height
                    )
                }
            }
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("appstore-screenshot-root-\(scene.rawValue)")
    }

    private func screenshotContent(
        compact: Bool,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 24 : 32) {
            AppStoreScreenshotHeader(compact: compact)

            if compact {
                VStack(alignment: .leading, spacing: 24) {
                    heroCopy(compact: compact)
                    scenePanel(compact: compact)
                }
            } else {
                HStack(alignment: .center, spacing: 44) {
                    heroCopy(compact: compact)
                        .frame(maxWidth: 430, alignment: .leading)
                    scenePanel(compact: compact)
                        .frame(maxWidth: .infinity)
                }
            }

            FooterProofRow(compact: compact)
        }
        .frame(maxWidth: compact ? 620 : 1180, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, verticalPadding)
        .padding(.bottom, max(verticalPadding, 42))
        .frame(minHeight: viewportHeight, alignment: .center)
    }

    private func heroCopy(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 22) {
            Text(scene.headline)
                .font(.system(size: compact ? 42 : 56, weight: .bold, design: .rounded))
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .foregroundStyle(BrandPalette.friendlyText)
                .fixedSize(horizontal: false, vertical: true)

            Text(scene.subheadline)
                .font(.system(size: compact ? 19 : 22, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(BrandPalette.friendlyTextDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ProofPill(label: "Temporary links", symbol: "timer")
                ProofPill(label: "Auto cleanup", symbol: "sparkles")
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func scenePanel(compact: Bool) -> some View {
        switch scene {
        case .shareFlow:
            ShareFlowPanel(compact: compact)
        case .retention:
            RetentionPanel(compact: compact)
        case .progress:
            ProgressPanel(compact: compact)
        case .history:
            HistoryPanel(compact: compact)
        case .pro:
            ProPanel(compact: compact)
        }
    }
}

private struct AppStoreScreenshotBackground: View {
    var body: some View {
        ZStack {
            BrandPalette.friendlyGround.ignoresSafeArea()
            LinearGradient(
                colors: [
                    BrandPalette.accentHot.opacity(0.18),
                    BrandPalette.accentFade.opacity(0.10),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [BrandPalette.amberAccent.hot.opacity(0.20), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 560
            )
            .ignoresSafeArea()
        }
    }
}

private struct AppStoreScreenshotHeader: View {
    let compact: Bool

    var body: some View {
        HStack {
            BrandLockup(markSize: compact ? 34 : 40, textSize: compact ? 22 : 26)
            Spacer()
            Text("Private file links")
                .font(.system(size: compact ? 14 : 15, weight: .semibold))
                .foregroundStyle(BrandPalette.friendlyTextDim)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(BrandPalette.friendlyCanvas.opacity(0.84))
                        .overlay(Capsule().stroke(BrandPalette.friendlyLine, lineWidth: 1))
                )
        }
    }
}

private struct ProofPill: View {
    let label: String
    let symbol: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BrandPalette.friendlyText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(BrandPalette.friendlyCanvas)
                    .overlay(Capsule().stroke(BrandPalette.friendlyLine, lineWidth: 1))
            )
    }
}

private struct FooterProofRow: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            FooterProof(symbol: "link", title: "Short link", value: "fastsha.red/x9k2")
            FooterProof(symbol: "clock", title: "Default expiry", value: "24 hours")
            if !compact {
                FooterProof(symbol: "icloud", title: "Pro sync", value: "iCloud")
            }
        }
    }
}

private struct FooterProof: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrandPalette.accentHot)
                .frame(width: 26, height: 26)
                .background(Circle().fill(BrandPalette.accentHot.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrandPalette.friendlyTextFaint)
                    .textCase(.uppercase)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.friendlyCanvas.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BrandPalette.friendlyLine, lineWidth: 1)
                )
        )
    }
}

private struct ScreenshotCard<Content: View>: View {
    let compact: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(compact ? 20 : 28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(BrandPalette.friendlyCanvas)
                    .shadow(color: BrandPalette.accentHot.opacity(0.12), radius: 30, x: 0, y: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(BrandPalette.friendlyLine, lineWidth: 1)
                    )
            )
    }
}

private struct ShareFlowPanel: View {
    let compact: Bool

    var body: some View {
        ScreenshotCard(compact: compact) {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                PanelTitle(symbol: "square.and.arrow.up", title: "Ready from the share sheet", subtitle: "Selected in Files")

                VStack(spacing: 12) {
                    FilePreviewRow(symbol: "doc.richtext", title: "launch-plan.pdf", detail: "14.2 MB PDF")
                    FilePreviewRow(symbol: "photo", title: "sprint-screenshot.png", detail: "3.4 MB image")
                }

                FlowStepDivider(label: "FastShared prepares a temporary link")

                LinkReadyCard()
            }
        }
    }
}

private struct RetentionPanel: View {
    let compact: Bool

    private let options = [
        ("1 hour", "Quick handoff", false),
        ("24 hours", "Default cleanup", true),
        ("7 days", "Review window", false),
        ("30 days", "Pro retention", false),
    ]

    var body: some View {
        ScreenshotCard(compact: compact) {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                PanelTitle(symbol: "timer", title: "Retention", subtitle: "Expires automatically")

                VStack(spacing: 12) {
                    ForEach(options, id: \.0) { option in
                        RetentionOption(title: option.0, subtitle: option.1, selected: option.2)
                    }
                }

                MiniInsightCard(symbol: "sparkles", title: "No cleanup chore", detail: "When time is up, the file is removed and the link stops working.")
            }
        }
    }
}

private struct ProgressPanel: View {
    let compact: Bool

    var body: some View {
        ScreenshotCard(compact: compact) {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                PanelTitle(symbol: "arrow.up.circle.fill", title: "Uploading", subtitle: "72% complete")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("product-demo.mov")
                            .font(.headline)
                            .foregroundStyle(BrandPalette.friendlyText)
                        Spacer()
                        Text("1.4 GB")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrandPalette.friendlyTextDim)
                    }

                    ProgressView(value: 0.72)
                        .tint(BrandPalette.accentHot)
                        .scaleEffect(x: 1, y: 1.7, anchor: .center)
                        .padding(.vertical, 6)

                    HStack {
                        ProgressStage(symbol: "checkmark.circle.fill", title: "Link reserved", active: true)
                        ProgressStage(symbol: "arrow.up", title: "Bytes moving", active: true)
                        ProgressStage(symbol: "doc.on.clipboard", title: "Copy next", active: false)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(BrandPalette.friendlySurface0)
                )

                LiveActivityMock()
            }
        }
    }
}

private struct HistoryPanel: View {
    let compact: Bool

    private let rows = [
        ("sprint-screenshot.png", "fastsha.red/k8p4", "42m left", "photo"),
        ("launch-plan.pdf", "fastsha.red/x9k2", "23h left", "doc.richtext"),
        ("product-demo.mov", "fastsha.red/m3v7", "6d left", "play.rectangle"),
    ]

    var body: some View {
        ScreenshotCard(compact: compact) {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                PanelTitle(symbol: "tray.full", title: "Recent links", subtitle: "Copy, share, or revoke")

                VStack(spacing: 10) {
                    ForEach(rows, id: \.1) { row in
                        HistoryPreviewRow(filename: row.0, link: row.1, expiry: row.2, symbol: row.3)
                    }
                }

                MiniInsightCard(symbol: "xmark.circle", title: "Revoke anytime", detail: "Stop a link before its timer ends.")
            }
        }
    }
}

private struct ProPanel: View {
    let compact: Bool

    var body: some View {
        ScreenshotCard(compact: compact) {
            VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                PanelTitle(symbol: "bolt.fill", title: "FastShared Pro", subtitle: "Built for frequent sharing")

                VStack(spacing: 12) {
                    ProTierRow(name: "Monthly", price: "$2.99", cadence: "per month", badge: nil)
                    ProTierRow(name: "Annual", price: "$19.99", cadence: "per year", badge: "Save 44%")
                    ProTierRow(name: "Lifetime", price: "$49.99", cadence: "one time", badge: "Family Sharing")
                }

                HStack(spacing: 10) {
                    ProFeature(symbol: "infinity", text: "Unlimited uploads")
                    ProFeature(symbol: "externaldrive", text: "2 GB files")
                    ProFeature(symbol: "icloud", text: "iCloud sync")
                }
            }
        }
    }
}

private struct PanelTitle: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BrandPalette.accentHot)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct FilePreviewRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(BrandPalette.accentHot)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandPalette.accentHot.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.friendlySurface0)
        )
    }
}

private struct FlowStepDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(BrandPalette.friendlyLine)
                .frame(height: 1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrandPalette.friendlyTextFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Rectangle()
                .fill(BrandPalette.friendlyLine)
                .frame(height: 1)
        }
    }
}

private struct LinkReadyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Link copied", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(BrandPalette.successGreen)
                Spacer()
                Text("24h")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandPalette.urgencyNormal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BrandPalette.urgencyNormalBgLight))
            }
            Text("fastsha.red/x9k2")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BrandPalette.friendlyText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text("Paste it anywhere. The file is removed automatically when the timer ends.")
                .font(.subheadline)
                .foregroundStyle(BrandPalette.friendlyTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandPalette.friendlySurface0)
        )
    }
}

private struct RetentionOption: View {
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? BrandPalette.accentHot : BrandPalette.friendlyTextFaint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BrandPalette.friendlyText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
            }
            Spacer()
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? BrandPalette.accentHot.opacity(0.12) : BrandPalette.friendlySurface0)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(selected ? BrandPalette.accentHot.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
    }
}

private struct MiniInsightCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(BrandPalette.accentHot)
                .frame(width: 34, height: 34)
                .background(Circle().fill(BrandPalette.accentHot.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandPalette.friendlyGround)
        )
    }
}

private struct ProgressStage: View {
    let symbol: String
    let title: String
    let active: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(active ? BrandPalette.accentHot : BrandPalette.friendlyTextFaint)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(active ? BrandPalette.friendlyText : BrandPalette.friendlyTextFaint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LiveActivityMock: View {
    var body: some View {
        HStack(spacing: 12) {
            PlaneArcMark(size: 36, framed: true, background: BrandPalette.ground)
            VStack(alignment: .leading, spacing: 2) {
                Text("FastShared")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                Text("product-demo.mov uploading")
                    .font(.caption)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
            }
            Spacer()
            Text("72%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(BrandPalette.accentHot)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrandPalette.friendlyGround)
        )
    }
}

private struct HistoryPreviewRow: View {
    let filename: String
    let link: String
    let expiry: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BrandPalette.accentHot)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BrandPalette.accentHot.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrandPalette.friendlyText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(link)
                    .font(.caption.monospaced())
                    .foregroundStyle(BrandPalette.friendlyTextDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            Text(expiry)
                .font(.caption.weight(.bold))
                .foregroundStyle(BrandPalette.urgencyNormal)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(BrandPalette.urgencyNormalBgLight))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(BrandPalette.friendlySurface0)
        )
    }
}

private struct ProTierRow: View {
    let name: String
    let price: String
    let cadence: String
    let badge: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(BrandPalette.friendlyText)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrandPalette.accentHot)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(BrandPalette.accentHot.opacity(0.12)))
                    }
                }
                Text(cadence)
                    .font(.caption)
                    .foregroundStyle(BrandPalette.friendlyTextDim)
            }
            Spacer()
            Text(price)
                .font(.title3.weight(.bold))
                .foregroundStyle(BrandPalette.friendlyText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(name == "Annual" ? BrandPalette.accentHot.opacity(0.12) : BrandPalette.friendlySurface0)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(name == "Annual" ? BrandPalette.accentHot.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        )
    }
}

private struct ProFeature: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BrandPalette.accentHot)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrandPalette.friendlyTextDim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandPalette.friendlyGround)
        )
    }
}
