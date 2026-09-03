import UIKit

/// Estilo de fundo aplicado a todas as páginas de uma seção — como o tipo de
/// papel de uma divisória de caderno físico (liso, pautado, quadriculado).
enum PageBackground: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: return "Liso"
        case .ruled: return "Pautado"
        case .grid: return "Quadriculado"
        }
    }

    /// Tom de papel — sempre um creme suave, igual folha de caderno de
    /// verdade, independente do tema claro/escuro do sistema.
    static let paperColor = UIColor(red: 0.98, green: 0.965, blue: 0.925, alpha: 1)

    func makeBackgroundColor() -> UIColor {
        switch self {
        case .blank:
            return Self.paperColor
        case .ruled:
            return UIColor(patternImage: Self.ruledPattern)
        case .grid:
            return UIColor(patternImage: Self.gridPattern)
        }
    }

    /// Se este estilo tem uma margem vertical (linha vermelha à esquerda,
    /// como caderno pautado escolar). A posição em `x` fica fixa na página.
    var marginX: CGFloat? {
        self == .ruled ? 44 : nil
    }

    private static let ruledPattern: UIImage = {
        let size = CGSize(width: 320, height: 34)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            paperColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor.systemBlue.withAlphaComponent(0.28).setStroke()
            let path = UIBezierPath()
            path.lineWidth = 1
            path.move(to: CGPoint(x: 0, y: size.height - 0.5))
            path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            path.stroke()
        }
    }()

    private static let gridPattern: UIImage = {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            paperColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor.systemGray2.withAlphaComponent(0.35).setStroke()
            let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            path.lineWidth = 0.75
            path.stroke()
        }
    }()
}
