import SwiftUI

/// The header's menus, rebuilt from the same catalogs Quick AI and Settings read.
@MainActor
enum QuickActionModelMenu {
    struct Menu {
        let content: PopoverMenuContent
        let highlight: Int
    }

    static func models(coordinator: QuickActionScreenCoordinator, session: QuickActionSession) -> Menu {
        var items = coordinator.modelGroups.flatMap { group in
            group.options.enumerated().map { index, option in
                PopoverMenuItem(
                    title: option.title, icon: option.menuIcon,
                    sectionTitle: index == 0 ? group.title : nil,
                    detail: session.model.map(option.matches) == true ? "✓" : nil
                ) {
                    coordinator.select(option)
                }
            }
        }
        let loading = coordinator.isModelCatalogLoading
        if loading {
            items.insert(
                PopoverMenuItem(
                    title: String(localized: "Loading models…"), icon: .blank, isLoading: true
                ) {}, at: 0)
        }
        let options = coordinator.modelGroups.flatMap(\.options)
        let selected = session.model.flatMap { model in options.firstIndex { $0.matches(model) } }
        return Menu(
            content: PopoverMenuContent(items: items),
            highlight: (selected ?? 0) + (loading ? 1 : 0))
    }

    static func efforts(coordinator: QuickActionScreenCoordinator, session: QuickActionSession) -> Menu {
        let selected = session.model?.effort
        let efforts = coordinator.efforts
        return Menu(
            content: PopoverMenuContent(
                items: efforts.map { effort in
                    PopoverMenuItem(
                        title: effort.title, icon: .blank, detail: effort.id == selected ? "✓" : nil
                    ) {
                        coordinator.select(effort)
                    }
                }),
            highlight: efforts.firstIndex { $0.id == selected } ?? 0)
    }

    static func languages(
        coordinator: QuickActionScreenCoordinator, session: QuickActionSession
    ) -> Menu {
        let languages = coordinator.languages
        let selected = session.language.minimalIdentifier
        return Menu(
            content: PopoverMenuContent(
                items: languages.map { language in
                    PopoverMenuItem(
                        title: TextTranslator.displayName(of: language), icon: .blank,
                        detail: language.minimalIdentifier == selected ? "✓" : nil
                    ) {
                        coordinator.select(language)
                    }
                }),
            highlight: languages.firstIndex { $0.minimalIdentifier == selected } ?? 0)
    }
}
