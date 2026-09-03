import SwiftUI

/// Paleta de cores usada na capa dos cadernos e nas abas de seção — como as
/// cores de cadernos e divisórias plásticas de fichário escolares.
enum NotebookColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Vermelho"
        case .orange: return "Laranja"
        case .yellow: return "Amarelo"
        case .green: return "Verde"
        case .teal: return "Azul-petróleo"
        case .blue: return "Azul"
        case .purple: return "Roxo"
        case .pink: return "Rosa"
        case .graphite: return "Grafite"
        }
    }

    var color: Color {
        switch self {
        case .red: return Color(red: 0.80, green: 0.24, blue: 0.24)
        case .orange: return Color(red: 0.88, green: 0.49, blue: 0.13)
        case .yellow: return Color(red: 0.84, green: 0.67, blue: 0.13)
        case .green: return Color(red: 0.20, green: 0.58, blue: 0.32)
        case .teal: return Color(red: 0.15, green: 0.55, blue: 0.55)
        case .blue: return Color(red: 0.22, green: 0.45, blue: 0.83)
        case .purple: return Color(red: 0.52, green: 0.35, blue: 0.78)
        case .pink: return Color(red: 0.83, green: 0.35, blue: 0.55)
        case .graphite: return Color(red: 0.36, green: 0.39, blue: 0.43)
        }
    }

    /// Escolhe uma cor da paleta de forma determinística a partir de um
    /// índice (ex: ordem de criação), pra dar variedade automática sem
    /// precisar de escolha manual.
    static func forOrder(_ order: Int) -> NotebookColor {
        let cases = allCases
        let index = ((order % cases.count) + cases.count) % cases.count
        return cases[index]
    }
}
