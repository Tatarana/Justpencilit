import Foundation
import PencilKit
import UIKit

/// A imagem de uma página para a estante de leitura da Caderneta (fase 2):
/// o papel (cor, pauta e margem) com o desenho por cima, em JPEG. Mesma
/// técnica do `PDFExportService` — `drawing.image(from:scale:)` a partir do
/// arquivo salvo, sem captura de tela —, mas a página inteira numa imagem só.
enum PageImageRenderer {
    /// Lado maior da imagem, em pixels: nítido num celular, leve para subir.
    static let maxSide: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.7

    struct Rendered {
        let jpeg: Data
        let width: Int
        let height: Int
    }

    @MainActor
    static func render(_ page: NotebookPage) -> Rendered? {
        let background = page.section?.backgroundStyle ?? .blank
        let isLeftHanded = UserDefaults.standard.bool(forKey: AppSettingsKeys.leftHandedMode)
        let drawing = DrawingStore.load(fileName: page.drawingFileName)
        let paper = PageGeometry.size(fitting: drawing)
        guard paper.width > 0, paper.height > 0 else { return nil }

        // Pontos de papel → pixels, sem passar de maxSide.
        let k = min(maxSide / max(paper.width, paper.height), 2)
        let pixelSize = CGSize(width: (paper.width * k).rounded(), height: (paper.height * k).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        // O PencilKit adapta a cor da tinta ao modo claro/escuro "atual";
        // fora de uma view isso pode esmaecer a tinta — força o claro.
        var strokes: UIImage?
        if !drawing.strokes.isEmpty {
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                strokes = drawing.image(from: CGRect(origin: .zero, size: paper), scale: k)
            }
        }

        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.scaleBy(x: k, y: k)
            background.makeBackgroundColor().setFill()
            UIRectFill(CGRect(origin: .zero, size: paper))
            if let marginX = background.marginX {
                let x = isLeftHanded ? paper.width - marginX : marginX
                UIColor.systemRed.withAlphaComponent(0.4).setFill()
                UIRectFill(CGRect(x: x, y: 0, width: 1.5, height: paper.height))
            }
            cg.restoreGState()
            strokes?.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        return Rendered(jpeg: jpeg, width: Int(pixelSize.width), height: Int(pixelSize.height))
    }
}
