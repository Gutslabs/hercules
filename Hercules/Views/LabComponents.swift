import SwiftUI
import LucideKit

// MARK: - Biçimlendirme yardımcıları

enum LabFormat {
    static func optimal(_ range: LabRange, decimals: Int = 1) -> String {
        "hedef \(range.display)"
    }

    /// Değişimin "iyi mi" yönü — katalogdaki yön semantiğine göre renklenir.
    static func deltaDirection(_ delta: Double, analyte: LabAnalyte?) -> Int {
        guard let analyte else { return 0 }
        switch analyte.direction {
        case .higherBetter: return delta > 0 ? 1 : -1
        case .lowerBetter:  return delta < 0 ? 1 : -1
        case .band:         return 0
        }
    }

    static func tooltip(for result: LabResult) -> String {
        var parts: [String] = [result.name]
        if let ref = result.displayReference { parts.append("Referans: \(ref)") }
        if let band = result.distinctOptimal {
            parts.append(optimal(band).capitalizedFirst)
        }
        parts.append("Durum: \(result.status.label)")
        if let note = result.analyte?.note { parts.append(note) }
        return parts.joined(separator: "\n")
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}
