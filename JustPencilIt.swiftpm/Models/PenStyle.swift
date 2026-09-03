import SwiftUI
import PencilKit

/// Cores de caneta oferecidas no app — de propósito sem branco, pra nunca
/// mais deixar o traço "sumir" no papel (era o que acontecia com a paleta
/// padrão do sistema, que sempre inclui branco como opção).
enum PenColor: String, CaseIterable, Identifiable {
    case black, blue, red, green, purple, orange

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .blue: return UIColor(red: 0.16, green: 0.40, blue: 0.85, alpha: 1)
        case .red: return UIColor(red: 0.82, green: 0.18, blue: 0.18, alpha: 1)
        case .green: return UIColor(red: 0.16, green: 0.55, blue: 0.26, alpha: 1)
        case .purple: return UIColor(red: 0.48, green: 0.25, blue: 0.75, alpha: 1)
        case .orange: return UIColor(red: 0.88, green: 0.47, blue: 0.09, alpha: 1)
        }
    }

    var color: Color { Color(uiColor) }
}

/// Tipo de ferramenta ativa no canvas.
enum PenKind: String, CaseIterable, Identifiable {
    case pen, marker, eraser

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Caneta"
        case .marker: return "Marcador"
        case .eraser: return "Borracha"
        }
    }

    func makeTool(color: PenColor) -> PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, color: color.uiColor)
        case .marker:
            return PKInkingTool(.marker, color: color.uiColor)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }
}
