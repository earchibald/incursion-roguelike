// See the Incursion LICENSE file for copyright information.
//
// The help window: a window of the app's own, not a macOS Help Book.
//
// Why not the native help. Apple's help viewer wants an indexed bundle of
// HTML written ahead of time. Half of this manual is not written ahead of
// time -- it is generated from whatever module the player is running, and
// the reference lists change with the ruleset. It also expects one document
// per app, whereas this shows two sources with different licences that must
// be told apart on screen. And it opens a separate application the player
// cannot arrange beside the game. Our own window is a few hundred lines and
// does all three.
//
// The window is deliberately independent of the game window: it does not
// pause the game, does not steal the engine's keyboard, and survives the
// game window being resized or full-screened.

import AppKit
import SwiftUI

final class HelpViewModel: ObservableObject {
    @Published var selection: HelpItem
    @Published var query: String = ""
    @Published var textSize: CGFloat
    /// An anchor within the current page that the reading pane should bring
    /// into view. Cleared when the page changes, because an anchor names a
    /// place in one page only.
    @Published var pendingAnchor: String?

    private var back: [HelpItem] = []
    private var forward: [HelpItem] = []

    let library = HelpLibrary.shared

    init() {
        selection = HelpLibrary.shared.firstItem()
        let saved = UserDefaults.standard.double(forKey: "helpTextSize")
        textSize = saved >= 9 ? CGFloat(saved) : 13
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func go(to item: HelpItem) {
        guard item != selection else { return }
        back.append(selection)
        forward.removeAll()
        pendingAnchor = nil
        selection = item
    }

    /// Jump within the page being read.
    func jump(to anchor: String) {
        // Reassigned even when it has not changed, so clicking the same
        // contents entry twice scrolls there twice.
        pendingAnchor = nil
        pendingAnchor = anchor
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(selection)
        pendingAnchor = nil
        selection = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(selection)
        pendingAnchor = nil
        selection = next
    }

    func setTextSize(_ size: CGFloat) {
        textSize = max(9, min(28, size))
        UserDefaults.standard.set(Double(textSize), forKey: "helpTextSize")
    }

    var theme: HelpTheme {
        HelpTheme(palette: UserDefaults.standard.bool(forKey: "softPalette")
                  ? .soft : .classic)
    }
}

struct HelpRootView: View {
    @ObservedObject var model: HelpViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            HelpDetailView(model: model)
        }
        .searchable(text: $model.query, placement: .sidebar,
                    prompt: "Search the manual and guides")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: model.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Back")
                Button(action: model.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .help("Forward")
            }
            ToolbarItemGroup {
                Button { model.setTextSize(model.textSize - 1) } label: {
                    Image(systemName: "textformat.size.smaller")
                }.help("Smaller text")
                Button { model.setTextSize(model.textSize + 1) } label: {
                    Image(systemName: "textformat.size.larger")
                }.help("Bigger text")
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.query.trimmingCharacters(in: .whitespaces).count >= 2 {
            let hits = model.library.search(model.query)
            List(hits, selection: Binding(
                get: { model.selection },
                set: { if let item = $0 { model.go(to: item) } })
            ) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).font(.body)
                    if !hit.snippet.isEmpty {
                        Text(hit.snippet).font(.caption)
                            .foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .tag(hit.item)
            }
            .overlay {
                if hits.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                }
            }
        } else {
            List(selection: Binding(
                get: { model.selection },
                set: { if let item = $0 { model.go(to: item) } })
            ) {
                ForEach(model.library.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Text(model.library.title(for: item)).tag(item)
                        }
                    }
                }
            }
        }
    }
}

struct HelpDetailView: View {
    @ObservedObject var model: HelpViewModel

    var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            // The attribution band. CC BY-SA wants the credit where the
            // reader of the work sees it, so it sits above the page and not
            // in a credits file: name, licence, and two links to check both.
            if case .wiki(let slug) = model.selection,
               let page = model.library.pages[slug] {
                HelpCreditBar(page: page, theme: theme, size: model.textSize)
            }
            content(theme: theme)
        }
        .background(Color(nsColor: theme.background))
        .navigationTitle(model.library.title(for: model.selection))
        .navigationSubtitle("Incursion Help")
    }

    @ViewBuilder
    private func content(theme: HelpTheme) -> some View {
        switch model.selection {
        case .topic(let id):
            if let topic = model.library.topics[id] {
                HelpTextView(
                    document: HelpRender.manual(
                        topic, theme: theme, size: model.textSize,
                        known: { model.library.topics[$0] != nil }),
                    theme: theme,
                    scrollTo: model.pendingAnchor,
                    onLink: handle)
            } else {
                missing("That topic is not in this build of the manual.", theme)
            }
        case .wiki(let slug):
            if let page = model.library.pages[slug] {
                HelpTextView(
                    document: HelpRender.markdown(page.body, theme: theme,
                                                  size: model.textSize + 1),
                    theme: theme, scrollTo: nil, onLink: handle)
            } else {
                missing("That guide is not in this build.", theme)
            }
        case .about:
            ScrollView { HelpAboutView(model: model, theme: theme).padding(28) }
        }
    }

    @ViewBuilder
    private func missing(_ text: String, _ theme: HelpTheme) -> some View {
        VStack {
            Text(text).foregroundColor(Color(nsColor: theme.body))
            if let problem = model.library.loadProblem {
                Text(problem).font(.caption)
                    .foregroundColor(Color(nsColor: theme.quiet))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A clicked link. Ours move the window; anything else is the web, and
    /// goes to the browser.
    private func handle(_ url: URL) -> Bool {
        guard let target = HelpLink.target(of: url) else {
            NSWorkspace.shared.open(url)
            return true
        }
        switch target.kind {
        case "topic":
            if model.library.topics[target.value] != nil {
                model.query = ""
                model.go(to: .topic(target.value))
            }
        case "anchor":
            model.jump(to: target.value)
        default:
            break
        }
        return true
    }
}

/// One line of credit and two links, above every vendored wiki page.
struct HelpCreditBar: View {
    let page: WikiPage
    let theme: HelpTheme
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(page.credit)
                .font(.system(size: max(10, size - 2)))
                .foregroundColor(Color(nsColor: theme.quiet))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Link("Read the original", destination: URL(string: page.source)!)
                Link("The \(page.license) licence",
                     destination: URL(string: page.licenseURL)!)
            }
            .font(.system(size: max(10, size - 2)))
            .foregroundColor(Color(nsColor: theme.link))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.background).brightness(0.06))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: theme.quiet).opacity(0.4))
                .frame(height: 1)
        }
    }
}

struct HelpAboutView: View {
    @ObservedObject var model: HelpViewModel
    let theme: HelpTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About This Help")
                .font(.system(size: model.textSize + 8, weight: .bold))
                .foregroundColor(Color(nsColor: theme.heading))

            group("The Manual and Reference", """
                These pages are the game's own manual. They are exported from \
                the engine at build time, so the races, classes, feats, skills \
                and spell lists are the ones in the module this copy of \
                Incursion actually plays -- not a description of some other \
                version. The same pages are available in-game by pressing ?.
                """)

            group("Getting Started", """
                These guides come from the Incursion Wiki, which is written by \
                players and covers what the manual does not: what to do first, \
                what kills new characters, which spells earn their slot. Each \
                page names its source and licence at the foot of the page.
                """)

            group("Licences", """
                The wiki pages are used under the Creative Commons \
                Attribution-ShareAlike 3.0 licence and stay under it; they are \
                separate documents shown by the app, not part of its code. The \
                game and its manual are covered by the Incursion licence and \
                the Open Gaming Licence, both of which are in Licenses and \
                Notices in the application menu, and the OGL is in this window \
                under Licences.
                """)

            HStack(spacing: 16) {
                Link("The Incursion Wiki",
                     destination: URL(string: "http://incursion.wikidot.com/")!)
                Link("CC BY-SA 3.0",
                     destination: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!)
            }
            .font(.system(size: model.textSize))
            .foregroundColor(Color(nsColor: theme.link))
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    @ViewBuilder
    private func group(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: model.textSize + 2, weight: .semibold))
                .foregroundColor(Color(nsColor: theme.heading))
            Text(body)
                .font(.system(size: model.textSize))
                .foregroundColor(Color(nsColor: theme.body))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One window, reused. Opening help twice should raise the window you
/// already have, not stack a second copy of a two-megabyte manual on it.
final class HelpWindowController: NSWindowController {
    static let shared = HelpWindowController()
    private let model = HelpViewModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Incursion Help"
        window.setFrameAutosaveName("IncursionHelpWindow")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 420)
        super.init(window: window)
        window.contentView = NSHostingView(rootView: HelpRootView(model: model))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// `topic` may carry an anchor: "races#DR" opens Races and scrolls to
    /// the drow. That is what a menu item pointing into a reference page
    /// needs, and it is how the anchor jump gets exercised without a mouse.
    func show(topic: String? = nil, query: String? = nil) {
        if let topic {
            let parts = topic.split(separator: "#", maxSplits: 1)
            let id = String(parts[0])
            if HelpLibrary.shared.topics[id] != nil {
                model.go(to: .topic(id))
                if parts.count > 1 { model.jump(to: String(parts[1])) }
            } else if HelpLibrary.shared.pages[id] != nil {
                model.go(to: .wiki(id))
            }
        }
        if let query { model.query = query }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
