// See the Incursion LICENSE file for copyright information.
//
// The reading pane: a plain NSTextView in a scroll view, wrapped for SwiftUI.
//
// It is read-only and selectable, lays out at a width the caller chooses (80
// monospaced columns for the manual, a comfortable measure for prose), and
// reports clicked links back instead of handing them to a browser.

import AppKit
import SwiftUI

struct HelpTextView: NSViewRepresentable {
    /// The rendered page.
    var document: HelpDocument
    var theme: HelpTheme
    /// Anchor to scroll to once the page is laid out, if any.
    var scrollTo: String?
    /// Called with a clicked link. Return true if it was handled here.
    var onLink: (URL) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let text = scroll.documentView as? NSTextView else { return scroll }

        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = true
        text.backgroundColor = theme.background
        text.textContainerInset = NSSize(width: 24, height: 20)
        text.delegate = context.coordinator
        // The pane is dark; without this the insertion bar and the selection
        // are invisible against it.
        text.insertionPointColor = theme.body
        text.selectedTextAttributes = [
            .backgroundColor: theme.link.withAlphaComponent(0.35),
            .foregroundColor: NSColor.white,
        ]
        text.linkTextAttributes = [
            .foregroundColor: theme.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]

        scroll.drawsBackground = true
        scroll.backgroundColor = theme.background
        scroll.hasVerticalScroller = true
        // A window narrower than eighty columns still has to be readable:
        // without this the surplus is simply clipped and nothing says so.
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        // Find (Cmd-F) over a megabyte of reference is worth having, and it
        // is one property.
        scroll.findBarPosition = .aboveContent
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true

        context.coordinator.apply(to: text, parent: self, force: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        text.backgroundColor = theme.background
        scroll.backgroundColor = theme.background
        context.coordinator.apply(to: text, parent: self, force: false)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HelpTextView
        /// What is currently in the view, so a redraw for an unrelated reason
        /// -- a window resize, a theme change -- does not re-typeset a
        /// megabyte of text and throw away the reader's scroll position.
        private var shownText: NSAttributedString?
        private var shownWidth: CGFloat = 0
        private var shownAnchor: String?

        init(_ parent: HelpTextView) { self.parent = parent }

        func apply(to text: NSTextView, parent: HelpTextView, force: Bool) {
            let changed = force || shownText !== parent.document.text
                || shownWidth != parent.document.width
            if changed {
                shownText = parent.document.text
                shownWidth = parent.document.width
                text.textStorage?.setAttributedString(parent.document.text)
                // A fixed layout width, with the text view free to be taller.
                text.minSize = NSSize(width: parent.document.width, height: 0)
                text.maxSize = NSSize(width: parent.document.width,
                                      height: .greatestFiniteMagnitude)
                text.isHorizontallyResizable = false
                text.isVerticallyResizable = true
                text.textContainer?.widthTracksTextView = false
                text.textContainer?.containerSize = NSSize(
                    width: parent.document.width,
                    height: .greatestFiniteMagnitude)
                text.frame = NSRect(x: 0, y: 0, width: parent.document.width,
                                    height: text.frame.height)
                if parent.scrollTo == nil {
                    text.scroll(NSPoint(x: 0, y: 0))
                }
                shownAnchor = nil
            }
            if let anchor = parent.scrollTo, anchor != shownAnchor || changed {
                shownAnchor = anchor
                if let location = parent.document.anchors[anchor] {
                    // Layout has to have happened before a character offset
                    // has a place on screen.
                    text.layoutManager?.ensureLayout(for: text.textContainer!)
                    text.scrollRangeToVisible(NSRange(location: location, length: 1))
                    // scrollRangeToVisible also scrolls sideways to put the
                    // character in view, which in an 80-column page means
                    // the left margin is cut off. The reader wants the line,
                    // not the character.
                    if let clip = text.enclosingScrollView?.contentView {
                        var origin = clip.bounds.origin
                        if origin.x != 0 {
                            origin.x = 0
                            clip.scroll(to: origin)
                            text.enclosingScrollView?.reflectScrolledClipView(clip)
                        }
                    }
                }
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            let url: URL?
            if let u = link as? URL { url = u }
            else if let s = link as? String { url = URL(string: s) }
            else { url = nil }
            guard let url else { return false }
            return parent.onLink(url)
        }
    }
}
