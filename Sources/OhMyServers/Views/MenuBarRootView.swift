import AppKit
import SwiftUI
import OhMyServersCore

struct MenuBarRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Graphite.muted)
                Text(L10n.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Graphite.muted)
                Spacer(minLength: 8)
                headerButton(L10n.settings) {
                    SettingsWindow.present(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if model.enabledSites.isEmpty {
                Text(L10n.noSitesHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.muted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ForEach(Array(model.enabledSites.enumerated()), id: \.element.id) { index, site in
                    if index > 0 {
                        Rectangle()
                            .fill(Graphite.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                    SiteSection(site: site)
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    headerButton(L10n.refresh, disabled: model.isRefreshing) {
                        model.refreshNow()
                    }
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                        .opacity(model.isRefreshing ? 1 : 0)
                }
                Spacer()
                headerButton(L10n.quit) { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 760)
        .background(Graphite.bg)
        .preferredColorScheme(.dark)
        .onAppear { model.refreshNow() }
    }

    private func headerButton(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Graphite.muted.opacity(disabled ? 0.4 : 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// One site's embed section: a small header plus the shared web view.
/// Observes the shared store so height updates re-render without
/// recreating the web view.
private struct SiteSection: View {
    let site: KomariSite
    @ObservedObject private var store = KomariWebStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(site.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Graphite.muted)
                .textCase(.uppercase)
                .tracking(0.6)

            if let url = site.url {
                KomariWebView(siteID: site.id, url: url)
                    .frame(height: store.contentHeight(siteID: site.id))
            } else {
                Text(L10n.invalidURL)
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.offline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
