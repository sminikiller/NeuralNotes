import UIKit
import NeuralNotesCore

@MainActor
extension CanvasHost {
    var editorKeyCommands: [UIKeyCommand] {
        let specs: [(String, UIKeyModifierFlags, String)] = [
            ("n", [.command, .shift], "Nuova pagina"), ("f", .command, "Cerca nel quaderno"), ("k", .command, "Lente AI"),
            ("0", .command, "Pagina intera"), ("+", .command, "Ingrandisci"), ("-", .command, "Riduci"),
            (".", .command, "Solo foglio"), ("a", .command, "Seleziona tutto"), ("x", .command, "Taglia selezione"),
            ("d", .command, "Duplica selezione"), (UIKeyCommand.inputLeftArrow, [], "Pagina precedente"),
            (UIKeyCommand.inputRightArrow, [], "Pagina successiva"), (UIKeyCommand.inputPageUp, [], "Pagina precedente"),
            (UIKeyCommand.inputPageDown, [], "Pagina successiva"), ("p", [], "Penna"), ("e", [], "Gomma"),
            ("h", [], "Evidenziatore"), ("l", [], "Lazo"), ("t", [], "Testo"), ("s", [], "Forme"),
            ("1", [], "Penna preferita 1"), ("2", [], "Penna preferita 2"), ("3", [], "Penna preferita 3"),
            ("4", [], "Penna preferita 4"), ("5", [], "Penna preferita 5")
        ]
        return specs.map { input, flags, title in
            let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(editorKey(_:)))
            command.discoverabilityTitle = title; return command
        }
    }
    @objc func editorKey(_ command: UIKeyCommand) {
        guard let model, model.editingTextID == nil, !model.interactionBusy, !model.navigating, !model.loading else { return }
        let input = command.input ?? "", flags = command.modifierFlags
        if flags.contains(.command) {
            switch input {
            case "n": Task { await model.addPage() }
            case "f": model.searchRequest += 1
            case "k": model.requestLens()
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
            default:
                if let index = Int(input), model.writingOptions.presets.indices.contains(index - 1) { model.usePreset(model.writingOptions.presets[index - 1]) }
            }
        }
    }
}
