# TreMana UI — Zen first, Glass second (macOS 27)

Native macOS SwiftUI + system toolbar, grouped Form, NavigationSplitView and
Table remain first-class. The visual design emphasizes information hierarchy,
quiet spacing and legible torrent data.

- The connection header and compact count indicators use **Apple Liquid Glass**
  (\`glassEffect\`, \`GlassEffectContainer\`) rather than handcrafted opacity or
  third-party visual frameworks.
- High-density torrent table remains opaque and readable: compact native
  progress bars, monospaced rates, SF Symbols for status, Dynamic Type-friendly
  text labels and accessible progress values.
- Quiet typography and system semantic colors automatically track light/dark
  appearance. Native UI honors macOS accessibility contrast/transparency
  settings; no animated custom material or forced color palette.
- No window-wide blur, floating glass panels over table content, decorative
  gradients, or layout jumps from toasts.
- Bottom status strip has fixed 48-point height to prevent layout shifts on
  refresh; it displays errors, connection state and last successful update.
- All prior RPC actions, connection profiles, Keychain storage, and refresh
  policy remain untouched.

Visual runtime acceptance on actual macOS 27, both light/dark modes, reduced
transparency, keyboard navigation and varying window widths still required.
