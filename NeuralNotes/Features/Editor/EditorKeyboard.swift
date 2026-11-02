import UIKit
import NeuralNotesCore

@MainActor
extension CanvasHost {
    var editorKeyCommands: [UIKeyCommand] {
        let specs: [(String, UIKeyModifierFlags, String)] = [
            ("f", [.command, .shift], "Cerca in tutti i quaderni"), ("t", .command, "Apri una scheda"), ("w", .command, "Chiudi questa scheda"),
            ("v", [.command, .shift], "Incolla senza formattazione"),
            ("n", [.command, .shift], "Nuova pagina"), ("f", .command, "Cerca nel quaderno"), ("k", .command, "Lente AI"),
            ("0", .command, "Pagina intera"), ("+", .command, "Ingrandisci"), ("-", .command, "Riduci"),
            (".", .command, "Solo foglio"), ("a", .command, "Seleziona tutto"), ("x", .command, "Taglia selezione"),
            ("d", .command, "Duplica selezione"), (UIKeyCommand.inputLeftArrow, [], "Pagina precedente"),
            (UIKeyCommand.inputRightArrow, [], "Pagina successiva"), (UIKeyCommand.inputPageUp, [], "Pagina precedente"),
            (UIKeyCommand.inputPageDown, [], "Pagina successiva"), ("p", [], "Penna"), ("e", [], "Gomma"),
            ("h", [], "Evidenziatore"), ("l", [], "Lazo"), ("t", [], "Testo"), ("s", [], "Forme"),
            ("g", [], "Goniometro"), ("r", [], "Righello"),
            ("1", [], "Penna preferita 1"), ("2", [], "Penna preferita 2"), ("3", [], "Penna preferita 3"),
            ("4", [], "Penna preferita 4"), ("5", [], "Penna preferita 5")
        ]
        return specs.map { input, flags, title in
            let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(editorKey(_:)))
            command.discoverabilityTitle = title; return command
        }
    }
    @objc func editorKey(_ command: UIKeyCommand) {
        if writingViewport != nil, let parent = model?.pagePresenter as? CanvasHost, parent !== self {
            parent.editorKey(command); return
        }
        guard let model, !model.hasActiveStroke, !model.navigating, !model.loading else { return }
        let input = command.input ?? "", flags = command.modifierFlags
        if model.editingTextID != nil {
            let leavesText = flags.contains(.command) && (input == "t" || input == "w" || (input == "f" && flags.contains(.shift)))
            guard leavesText else { return }; textInput?.finishEditing()
        }
        if flags.contains(.command) {
            switch input {
            case "n": Task { await model.addPage() }
            case "f": if flags.contains(.shift) { model.globalSearchRequest += 1 } else { model.searchRequest += 1 }
            case "t": model.openNotebookRequest += 1
            case "w": model.closeNotebookRequest += 1
            case "v": if flags.contains(.shift) { Task { await model.pasteSelection(plainText: true) } }
            case "k": model.chooseTool(model.tool == .lens ? .pen : .lens)
            case "0": fitPage(animated: true)
            case "+", "-": canvas.setZoomScale(min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, canvas.zoomScale * (input == "+" ? 1.25 : 0.8))), animated: true)
            case ".": model.focusRequest += 1
            case "a": model.chooseTool(.objects); model.selectAll()
            case "x": model.cutSelection()
            case "d": model.duplicateSelectedObject()
            default: break
            }
        } else {
            switch input {
            case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputPageUp: Task { await model.turnPage(-1) }
            case UIKeyCommand.inputRightArrow, UIKeyCommand.inputPageDown: Task { await model.turnPage(1) }
            case "p": model.chooseTool(.pen)
            case "e": model.chooseTool(.eraser)
            case "h": model.chooseTool(.marker)
            case "l": model.chooseTool(.lasso)
            case "t": model.chooseTool(.text)
            case "s": model.chooseTool(.rectangle)
            case "g": model.chooseTool(.protractor)
            case "r": model.chooseTool(.ruler)
            default:
                if let index = Int(input), model.writingOptions.presets.indices.contains(index - 1) { model.usePreset(model.writingOptions.presets[index - 1]) }
            }
        }
    }
}
