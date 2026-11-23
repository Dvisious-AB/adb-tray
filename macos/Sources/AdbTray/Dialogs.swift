import AppKit

enum Dialogs {
    /// A modal form with one text field per `(caption, default)`. Returns the trimmed values, or nil on cancel.
    static func ask(title: String, fields: [(String, String)]) -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: tr("OK"))
        alert.addButton(withTitle: tr("Cancel"))

        let textFields = fields.map { _, value -> NSTextField in
            let field = NSTextField(string: value)
            field.widthAnchor.constraint(equalToConstant: 220).isActive = true
            return field
        }
        let rows = zip(fields, textFields).map { field, textField -> [NSView] in
            [NSTextField(labelWithString: field.0), textField]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid
        alert.window.initialFirstResponder = textFields.first

        // A menu bar app is never frontmost by itself; without this the dialog opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return textFields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
