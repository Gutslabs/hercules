import Foundation

/// SF Symbols adı → Lucide ikon adı. Migration'ı tek noktadan deterministik kılar:
/// `Image(systemName: X)` → `Lucide(sf: X)` (enum prop'ları/ternary/dinamik ifadeler
/// değişmeden çalışır). Lucide outline-only olduğu için `.fill` varyantları aynı ikona
/// düşer; dolu/seçili durumu RENKLE gösterilir (heart, pin, vb.).
public enum LucideSF {
    public static let map: [String: String] = [
        // Oklar / navigasyon
        "arrow.clockwise": "rotate-cw",
        "arrow.triangle.2.circlepath": "refresh-cw",
        "arrow.up": "arrow-up",
        "arrow.down": "arrow-down",
        "arrow.left": "arrow-left",
        "arrow.right": "arrow-right",
        "arrow.up.right": "arrow-up-right",
        "arrow.up.right.square": "external-link",
        "arrow.up.arrow.down": "arrow-up-down",
        "arrow.down.circle": "circle-arrow-down",
        "arrow.uturn.backward": "undo-2",
        "chevron.up": "chevron-up",
        "chevron.down": "chevron-down",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "chevron.up.chevron.down": "chevrons-up-down",

        // Aksiyonlar
        "xmark": "x",
        "xmark.circle": "circle-x",
        "xmark.circle.fill": "circle-x",
        "checkmark": "check",
        "checkmark.circle.fill": "circle-check",
        "checkmark.seal": "badge-check",
        "checkmark.seal.fill": "badge-check",
        "plus": "plus",
        "plus.circle": "circle-plus",
        "plus.circle.fill": "circle-plus",
        "minus": "minus",
        "minus.circle.fill": "circle-minus",
        "trash": "trash-2",
        "trash.fill": "trash-2",
        "pencil": "pencil",
        "square.and.pencil": "square-pen",
        "square.and.arrow.up": "share",
        "square.and.arrow.down": "download",
        "square.on.square": "copy",
        "doc.on.doc": "copy",
        "doc.text.magnifyingglass": "file-search",
        "magnifyingglass": "search",
        "link": "link",
        "bookmark": "bookmark",
        "pin": "pin",
        "pin.fill": "pin",
        "pin.badge.plus": "pin",
        "return": "corner-down-left",
        "escape": "x",
        "stop.fill": "square",
        "square.stack.3d.up": "layers",
        "largecircle.fill.circle": "circle-dot",
        "circle": "circle",

        // Medya / giriş
        "mic": "mic",
        "mic.fill": "mic",
        "camera": "camera",
        "camera.fill": "camera",
        "photo": "image",
        "photo.badge.plus": "image-plus",
        "photo.on.rectangle": "images",
        "folder": "folder",
        "doc": "file",
        "speaker.wave.2": "volume-2",
        "waveform": "audio-lines",
        "iphone.and.arrow.forward": "smartphone",
        "character.cursor.ibeam": "text-cursor",
        "text.alignleft": "align-left",
        "text.quote": "quote",
        "quote.bubble": "quote",

        // Kişi / domain
        "house": "house",
        "person": "user",
        "person.2": "users",
        "person.2.fill": "users",
        "person.crop.circle": "circle-user",
        "person.text.rectangle": "contact",
        "person.badge.key": "key-round",
        "book": "book",
        "book.closed": "book",
        "books.vertical": "library",
        "fork.knife": "utensils",
        "takeoutbag.and.cup.and.straw": "utensils-crossed",
        "drop": "droplet",
        "scissors": "scissors",
        "sun.max.fill": "sun",
        "moon.fill": "moon",
        "moon.stars.fill": "moon-star",
        "birthday.cake.fill": "cake",
        "tshirt": "shirt",
        "calendar": "calendar",
        "calendar.badge.clock": "calendar-clock",
        "clock.fill": "clock",
        "clock": "clock",
        "ruler": "ruler",
        "scalemass": "scale",
        "scalemass.fill": "scale",
        "target": "target",
        "scope": "crosshair",
        "gauge.medium": "gauge",
        "gearshape": "settings",
        "wrench.and.screwdriver": "wrench",
        "wrench.adjustable": "wrench",
        "terminal": "terminal",
        "laptopcomputer": "laptop",
        "key": "key-round",
        "lock": "lock",
        "lock.fill": "lock",
        "lock.square.stack": "lock",
        "info.circle": "info",
        "lightbulb.fill": "lightbulb",
        "heart": "heart",
        "heart.fill": "heart",
        "flame.fill": "flame",
        "flame": "flame",
        "bolt.fill": "zap",
        "tag": "tag",
        "exclamationmark.circle.fill": "circle-alert",
        "arrow.up.forward.circle.fill": "circle-arrow-up",
        "minus.circle": "circle-minus",

        // AI / asistan — eskiden karışıktı (sparkles/wand/brain), artık hep `sparkles`.
        "sparkles": "sparkles",
        "sparkle.magnifyingglass": "sparkles",
        "wand.and.stars": "sparkles",
        "brain.head.profile": "brain",
        "brain": "brain",

        // Uyarı / durum
        "exclamationmark.triangle": "triangle-alert",
        "exclamationmark.triangle.fill": "triangle-alert",
        "globe": "globe",
        "globe.americas": "globe",
        "tray": "inbox",
        "tray.and.arrow.down": "download",

        // Grid / grafik / liste
        "square.grid.2x2": "grid-2x2",
        "list.bullet": "list",
        "chart.bar": "chart-column",
        "chart.bar.xaxis": "chart-column",
        "chart.dots.scatter": "chart-scatter",
        "chart.line.uptrend.xyaxis": "trending-up",
        "chart.xyaxis.line": "chart-line",

        // Fitness
        "figure.run": "footprints",
        "figure.strengthtraining.traditional": "dumbbell",
        "dumbbell": "dumbbell",

        // Sohbet
        "bubble.left.and.bubble.right": "messages-square",
        "bubble.left.and.text.bubble.right": "messages-square",
    ]

    /// SF adından Lucide ikon adını çözer. Eşleşme yoksa `.fill`/`.circle` ekini atıp
    /// tekrar dener; yine yoksa görünür placeholder (`circle-help`) — eksiği fark etmek için.
    public static func lucideName(forSF sf: String) -> String {
        if let n = map[sf] { return n }
        let stripped = sf
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".circle", with: "")
        if let n = map[stripped] { return n }
        return "circle-help"
    }
}
