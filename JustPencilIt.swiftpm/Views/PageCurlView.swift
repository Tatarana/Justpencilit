import SwiftUI
import UIKit
import PencilKit

/// Virada de página nativa do iOS (o "page curl" do app Livros), via
/// `UIPageViewController`. Já vem com o gesto de puxar a borda da folha
/// acompanhando o dedo, e com toque na lateral pra virar.
///
/// Só o dedo vira página — a Apple Pencil fica livre pra escrever até na
/// beirada da folha sem disparar a virada.
struct PageCurlView<Content: View>: UIViewControllerRepresentable {
    /// IDs das páginas, na ordem. Cada folha é identificada pelo ID (e não
    /// pela posição), pra continuar certa se páginas forem criadas/apagadas.
    var pageIDs: [UUID]
    @Binding var selectedIndex: Int
    /// Monta a folha de uma página. `isCurrent` é falso pras vizinhas que o
    /// sistema pré-carrega durante a virada.
    var content: (_ pageID: UUID, _ isCurrent: Bool) -> Content
    /// Avisa quando uma virada começa/termina (pra travar os botões ‹ ›).
    var onTurningChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        pageVC.view.backgroundColor = .clear

        let fingerOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for recognizer in pageVC.gestureRecognizers {
            recognizer.allowedTouchTypes = fingerOnly
            if recognizer.view == nil {
                pageVC.view.addGestureRecognizer(recognizer)
            }
            // O gesto de virar aceitava também arrasto vertical (curvando a
            // folha pelo canto) e nunca "desistia" — e a rolagem do papel,
            // que espera ele desistir, ficava travada (menos na 1ª página,
            // onde não há folha anterior). Agora só vira com arrasto
            // horizontal; na vertical ele desiste na hora e o papel rola.
            if recognizer is UIPanGestureRecognizer {
                let gate = HorizontalPanGate(original: recognizer.delegate)
                recognizer.delegate = gate
                context.coordinator.panGates.append(gate)
            }
        }

        if !pageIDs.isEmpty {
            let start = min(max(selectedIndex, 0), pageIDs.count - 1)
            if let first = context.coordinator.makeController(for: start, isCurrent: true) {
                pageVC.setViewControllers([first], direction: .forward, animated: false)
            }
        }
        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard !pageIDs.isEmpty else { return }
        let target = min(max(selectedIndex, 0), pageIDs.count - 1)

        guard let current = pageVC.viewControllers?.first as? PageHostController<Content>,
              let currentIndex = coordinator.index(of: current) else {
            // Folha atual sumiu (página apagada, troca de seção): mostra a
            // certa direto, sem animação.
            if let vc = coordinator.makeController(for: target, isCurrent: true) {
                pageVC.setViewControllers([vc], direction: .forward, animated: false)
            }
            return
        }

        if currentIndex == target {
            // Mesma folha: só atualiza o conteúdo (caneta, cor, gatilhos...).
            current.rootView = content(pageIDs[target], true)
        } else if !coordinator.isTurning {
            // Botões ‹ › / nova página: vira com a mesma animação do gesto.
            guard let vc = coordinator.makeController(for: target, isCurrent: true) else { return }
            let direction: UIPageViewController.NavigationDirection = target > currentIndex ? .forward : .reverse
            coordinator.setTurning(true)
            pageVC.setViewControllers([vc], direction: direction, animated: true) { _ in
                coordinator.setTurning(false)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        private(set) var isTurning = false
        // O delegate de um gesto é "weak" — guardamos aqui pra não sumir.
        var panGates: [HorizontalPanGate] = []

        init(_ parent: PageCurlView) {
            self.parent = parent
        }

        func setTurning(_ turning: Bool) {
            isTurning = turning
            let callback = parent.onTurningChange
            DispatchQueue.main.async { callback(turning) }
        }

        func makeController(for index: Int, isCurrent: Bool) -> PageHostController<Content>? {
            guard parent.pageIDs.indices.contains(index) else { return nil }
            let id = parent.pageIDs[index]
            let vc = PageHostController(rootView: parent.content(id, isCurrent))
            vc.pageID = id
            vc.view.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
            return vc
        }

        func index(of viewController: UIViewController) -> Int? {
            guard let host = viewController as? PageHostController<Content>,
                  let id = host.pageID else { return nil }
            return parent.pageIDs.firstIndex(of: id)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return makeController(for: index - 1, isCurrent: false)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return makeController(for: index + 1, isCurrent: false)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                willTransitionTo pendingViewControllers: [UIViewController]) {
            setTurning(true)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            setTurning(false)
            guard completed,
                  let current = pageViewController.viewControllers?.first,
                  let newIndex = index(of: current) else { return }
            if parent.selectedIndex != newIndex {
                parent.selectedIndex = newIndex
            }
        }
    }
}

/// Folha hospedada no UIPageViewController — guarda o ID da página pra saber
/// qual é a anterior/próxima.
final class PageHostController<Content: View>: UIHostingController<Content> {
    var pageID: UUID?
}

/// Fica na frente do delegate original do gesto de virar página: recusa o
/// início se o arrasto for mais vertical que horizontal, e repassa todo o
/// resto pro delegate original (o próprio UIPageViewController).
final class HorizontalPanGate: NSObject, UIGestureRecognizerDelegate {
    weak var original: UIGestureRecognizerDelegate?

    init(original: UIGestureRecognizerDelegate?) {
        self.original = original
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view {
            var motion = pan.velocity(in: view)
            if motion == .zero {
                motion = pan.translation(in: view)
            }
            if abs(motion.y) > abs(motion.x) {
                return false
            }
            // Folha ampliada com a pinça: arrastar de lado rola a folha em
            // vez de virar a página (pra virar, use ‹ › ou volte o zoom).
            var hit = view.hitTest(pan.location(in: view), with: nil)
            while let current = hit {
                if let canvas = current as? PKCanvasView {
                    if canvas.zoomScale > canvas.minimumZoomScale + 0.001 {
                        return false
                    }
                    break
                }
                hit = current.superview
            }
        }
        return original?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }
}
