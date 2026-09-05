import UIKit

class MarkdownViewController: UIViewController, UITextViewDelegate {

    // MARK: - Properties
    var markdownTextView: UITextView!

    var onSave: ( (String,String,Int,Int) -> () )?

    private var enableMarkdownLinks = true

    private var textView: UITextView!  // Main editor - shows raw markdown
    private var toolbar: UIToolbar!
    private var isPreviewMode = true  // Will be set in viewDidLoad based on content

    // Constraint for adjusting bottom when keyboard appears
    private var textViewBottomConstraint: NSLayoutConstraint!

    // Sample markdown text for testing (you can set this externally)
    var markdownText = ""

    // Track if we're currently updating to prevent infinite loops
    private var isUpdatingText = false
    
    // Debug flag: force the fallback parser even if AttributedString parsing succeeds
    // Set to true to use the fallback parser which handles line breaks better
    private var forceFallbackParser = true

    private let markdownFontStep: CGFloat = 2
    private let markdownFontMinimum: CGFloat = 12
    private let markdownFontMaximum: CGFloat = 28
    private var markdownFontSize: CGFloat = 16
    
    @objc func escapex(){
       // Save will happen automatically in viewWillDisappear
       dismiss(animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
     
    private var hasAlreadySaved = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupConstraints()

        // Smart start: preview hvis innhold finnes, edit hvis tomt
        if markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Tomt felt - start i edit mode
            isPreviewMode = false
            textView.isHidden = false
            markdownTextView.isHidden = true

            // Update toolbar button to show "eye" (preview) icon
            if let items = toolbar.items, items.count > 0 {
                toolbar.items?[0] = UIBarButtonItem(
                    image: UIImage(systemName: "eye"),
                    style: .plain,
                    target: self,
                    action: #selector(refreshFormatting)
                )
            }

            // Gjør textView til første responder - vis tastatur automatisk
            textView.becomeFirstResponder()
        } else {
            // Har innhold - start i preview mode (Apple Notes-stil)
            isPreviewMode = true
            textView.isHidden = true
            markdownTextView.isHidden = false
            showPreviewMode()
        }

        // Keyboard shortcuts
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapex))
        addKeyCommand(escape)

        // F1 = Toggle between edit and preview
        let f1 = UIKeyCommand(input: UIKeyCommand.f1, modifierFlags: [], action: #selector(refreshFormatting))
        f1.title = "Toggle Edit/Preview"
        addKeyCommand(f1)

        // Set up presentation controller delegate to catch swipe-down dismissal
        if let presentationController = presentationController {
            presentationController.delegate = self
        }

        // Register for keyboard notifications
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        let keyboardHeight = keyboardFrame.height
        textViewBottomConstraint.constant = -keyboardHeight - 16

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        textViewBottomConstraint.constant = -16

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        print("========== [viewWillDisappear] ==========")
        print("DEBUG viewWillDisappear: isPreviewMode=\(isPreviewMode)")
        print("DEBUG viewWillDisappear: textView.text length: \(textView.text?.count ?? 0)")
        print("DEBUG viewWillDisappear: textView.text: '\(textView.text ?? "nil")'")

        // Auto-save when view is disappearing, regardless of how it was dismissed
        saveIfNeeded()
    }

    private func saveIfNeeded() {
        print("DEBUG saveIfNeeded: hasAlreadySaved=\(hasAlreadySaved)")
        guard !hasAlreadySaved else {
            print("DEBUG saveIfNeeded: SKIPPED - already saved!")
            return
        }

        hasAlreadySaved = true

        let textToSave = textView.text ?? ""
        print("DEBUG saveIfNeeded: saving textView.text with \(textToSave.count) chars")
        print("DEBUG saveIfNeeded: textToSave content: '\(textToSave)'")
        print("DEBUG saveIfNeeded: calling onSave with i1=2, i2=3")

        onSave?(textToSave, "", 2, 3)

        print("DEBUG saveIfNeeded: onSave completed!")
    }
    
    // web link
    private func applyLinks(_ attributedString: NSMutableAttributedString) {
        guard enableMarkdownLinks else { return }
        // [title](https://example.com)
        let pattern = #"\[(.*?)\]\((https?://[^\s)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let s = attributedString.string as NSString
        let range = NSRange(location: 0, length: s.length)
        let matches = regex.matches(in: attributedString.string, options: [], range: range)

        for m in matches.reversed() {
            guard m.numberOfRanges == 3 else { continue }
            let title = s.substring(with: m.range(at: 1))
            let urlStr = s.substring(with: m.range(at: 2))

            let repl = NSMutableAttributedString(string: title)
            if let url = URL(string: urlStr) {
                repl.addAttribute(.link, value: url, range: NSRange(location: 0, length: repl.length))
            }
            // Optional visual styling (can be dropped; linkTextAttributes are used anyway)
            repl.addAttributes([
                .foregroundColor: UIColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: NSRange(location: 0, length: repl.length))

            attributedString.replaceCharacters(in: m.range(at: 0), with: repl)
        }
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        // title = "Markdown Editor"  // Fjernet - ingen tittel ønsket

        setupTextViews()
        setupToolbar()
        // setupNavigationBar()  // Fjernet - Done-knappen lagrer ikke
    }
    
    private func showPreviewMode() {
        // Show formatted preview
        textView.isHidden = true
        markdownTextView.isHidden = false
        markdownTextView.backgroundColor = .systemBackground

        // Render the markdown content
        renderMarkdown()
    }

    private func showEditMode() {
        // Show raw markdown editor
        textView.isHidden = false
        markdownTextView.isHidden = true
    }
    
    private func setupTextViews() {
        // Main text editor
        textView = UITextView()
        textView.text = markdownText
        textView.font = monospacedBodyFont()
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.delegate = self  // Set delegate for edit menu customization

        // Show "Done" over the keyboard - save and close like ESC
        // Also show "Lim inn" button if clipboard has content
        textView.addDoneToolbar(target: self, doneAction: #selector(donePressed), pasteAction: #selector(pasteFromClipboard))

        // Tap anywhere to just close the keyboard (not save and exit)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        // Markdown view (preview) - Read-only formatted view
        markdownTextView = UITextView()
        markdownTextView.isEditable = false  // Read-only preview
        markdownTextView.backgroundColor = .systemBackground
        markdownTextView.textColor = .label
        markdownTextView.layer.borderWidth = 1
        markdownTextView.layer.borderColor = UIColor.separator.cgColor
        markdownTextView.layer.cornerRadius = 8
        markdownTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        markdownTextView.isHidden = true  // Hidden by default - show on refresh

        // Make links tappable and text selectable
        markdownTextView.isSelectable = true
        markdownTextView.dataDetectorTypes = .link
        markdownTextView.delegate = self  // Enable custom edit menu in preview mode!

        view.addSubview(textView)
        view.addSubview(markdownTextView)
    }
    
    private func setupToolbar() {
        toolbar = UIToolbar()
        toolbar.backgroundColor = .systemBackground

        // Toggle button - starts as "pencil" (edit) since we start in preview mode
        let toggleButton = UIBarButtonItem(
            image: UIImage(systemName: "pencil"),
            style: .plain,
            target: self,
            action: #selector(refreshFormatting)
        )

        let copyButton = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.clipboard"),
            style: .plain,
            target: self,
            action: #selector(copyText)
        )

        let zoomOutButton = UIBarButtonItem(
            image: UIImage(systemName: "minus"),
            style: .plain,
            target: self,
            action: #selector(decreaseFontSize)
        )

        let zoomInButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(increaseFontSize)
        )

        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareText)
        )

        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearTextTapped)
        )

        let exitButton = UIBarButtonItem(
            image: UIImage(systemName: "x.circle"),
            style: .plain,
            target: self,
            action: #selector(donePressed)
        )

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [toggleButton, flexSpace, copyButton, flexSpace, zoomOutButton, zoomInButton, flexSpace, shareButton, flexSpace, clearButton, flexSpace, exitButton]
        view.addSubview(toolbar)
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(donePressed)
        )
    }
    
    // MARK: - Constraints
    private func setupConstraints() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        markdownTextView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // Create the bottom constraint separately so we can adjust it for keyboard
        textViewBottomConstraint = textView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)

        NSLayoutConstraint.activate([
            // Toolbar constraints - NÅ PÅ TOPPEN
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Text view constraints - UNDER TOOLBAR
            textView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textViewBottomConstraint,  // Use the adjustable constraint

            // Markdown view constraints (same as text view)
            markdownTextView.topAnchor.constraint(equalTo: textView.topAnchor),
            markdownTextView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            markdownTextView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            markdownTextView.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc private func refreshFormatting() {
        print("DEBUG refreshFormatting: isPreviewMode=\(isPreviewMode)")
        print("DEBUG refreshFormatting: textView.text length=\(textView.text?.count ?? 0)")

        // Toggle between edit and preview mode
        if isPreviewMode {
            // Currently showing preview, switch to edit
            print("DEBUG: Switching TO edit mode")
            showEditMode()
            isPreviewMode = false

            // Update button icon to show "eye" (preview)
            if let items = toolbar.items, items.count > 0 {
                toolbar.items?[0] = UIBarButtonItem(
                    image: UIImage(systemName: "eye"),
                    style: .plain,
                    target: self,
                    action: #selector(refreshFormatting)
                )
            }
        } else {
            // Currently showing edit, switch to preview
            print("DEBUG: Switching TO preview mode")
            print("DEBUG: textView is nil: \(textView == nil)")
            print("DEBUG: markdownTextView is nil: \(markdownTextView == nil)")
            print("DEBUG: textView.text before renderMarkdown: '\(textView.text ?? "")'")

            do {
                print("DEBUG: About to call showPreviewMode()")
                showPreviewMode()
                print("DEBUG: showPreviewMode() completed")
            }

            isPreviewMode = true

            // Update button icon to show "pencil" (edit)
            if let items = toolbar.items, items.count > 0 {
                toolbar.items?[0] = UIBarButtonItem(
                    image: UIImage(systemName: "pencil"),
                    style: .plain,
                    target: self,
                    action: #selector(refreshFormatting)
                )
            }
        }

        print("DEBUG refreshFormatting: After toggle, textView.text length=\(textView.text?.count ?? 0)")
    }

    @objc private func copyText() {
        UIPasteboard.general.string = textView.text

        // Show feedback
        let alert = UIAlertController(title: nil, message: "Copied to clipboard", preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            alert.dismiss(animated: true)
        }
    }

    @objc private func pasteFromClipboard() {
        // Hent tekst fra clipboard
        guard let clipboardText = UIPasteboard.general.string else { return }

        // Hvis vi har valgt tekst, erstatt den
        if let selectedRange = textView.selectedTextRange,
           let selectedText = textView.text(in: selectedRange),
           !selectedText.isEmpty {
            textView.replace(selectedRange, withText: clipboardText)
        } else {
            // Ellers, legg til på slutten av eksisterende tekst
            if textView.text.isEmpty {
                textView.text = clipboardText
            } else {
                textView.text += "\n" + clipboardText
            }
        }

        // Oppdater toolbar (kan ha endret clipboard status)
        textView.addDoneToolbar(target: self, doneAction: #selector(donePressed), pasteAction: #selector(pasteFromClipboard))
    }
    
    @objc private func shareText() {
        let activityVC = UIActivityViewController(activityItems: [textView.text ?? ""], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    @objc private func clearTextTapped() {
        guard !(textView.text ?? "").isEmpty else { return }

        let alert = UIAlertController(
            title: "Fjern tekst",
            message: "Er du sikker på at du vil fjerne all tekst i notatfeltet?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Avbryt", style: .cancel))
        alert.addAction(UIAlertAction(title: "Fjern", style: .destructive) { [weak self] _ in
            self?.clearText()
        })
        present(alert, animated: true)
    }

    private func clearText() {
        textView.text = ""
        if isPreviewMode {
            renderMarkdown()
        }
    }

    @objc private func decreaseFontSize() {
        updateMarkdownFontSize(markdownFontSize - markdownFontStep)
    }

    @objc private func increaseFontSize() {
        updateMarkdownFontSize(markdownFontSize + markdownFontStep)
    }

    private func updateMarkdownFontSize(_ newSize: CGFloat) {
        let clamped = min(max(newSize, markdownFontMinimum), markdownFontMaximum)
        guard clamped != markdownFontSize else { return }

        markdownFontSize = clamped
        applyCurrentFontSize()
    }

    private func applyCurrentFontSize() {
        textView.font = monospacedBodyFont()

        if isPreviewMode {
            renderMarkdown()
        }
    }
    
    @objc private func donePressed() {
        // Save will happen automatically in viewWillDisappear
        dismiss(animated: true)
    }
    
    // MARK: - Markdown Rendering
    private func renderMarkdown() {
        NSLog("========== [renderMarkdown] ENTRY ==========")
        print("[renderMarkdown] ENTRY - self.textView is nil: \(self.textView == nil)")

        guard self.textView != nil else {
            NSLog("[renderMarkdown] ERROR: self.textView is nil!")
            print("[renderMarkdown] ERROR: self.textView is nil!")
            return
        }

        let text = self.textView.text ?? ""

        NSLog("[renderMarkdown] Text: %@", text)
        print("[renderMarkdown] Starting render, forceFallback=\(forceFallbackParser)")
        print("[renderMarkdown] Text to render: '\(text)'")
        print("[renderMarkdown] Text length: \(text.count)")

        if forceFallbackParser {
            NSLog("[renderMarkdown] Using fallback parser (forced)")
            print("[renderMarkdown] Using fallback parser (forced)")
            let result = parseMarkdown(text)
            NSLog("[renderMarkdown] parseMarkdown returned, length: %d", result.length)
            print("[renderMarkdown] Fallback result length: \(result.length)")
            print("[renderMarkdown] Fallback result string: '\(result.string)'")

            // DEBUG: Check if result has font attributes
            if result.length > 0 {
                let attrs = result.attributes(at: 0, effectiveRange: nil)
                NSLog("[renderMarkdown] First char attributes: %@", attrs.description)
                print("[renderMarkdown] First char has font: \(attrs[.font] != nil)")
            }

            markdownTextView.attributedText = result
            NSLog("[renderMarkdown] Set markdownTextView.attributedText")
            print("[renderMarkdown] Set markdownTextView.attributedText")

            // Verify it was set
            if let setAttr = markdownTextView.attributedText {
                NSLog("[renderMarkdown] Verification: markdownTextView.attributedText.length = %d", setAttr.length)
            }

            return
        }

        do {
            print("[renderMarkdown] Trying AttributedString parser")
            let attributedString = try createStyledAttributedString(from: text)
            let nsAttrString = NSAttributedString(attributedString)

            print("[renderMarkdown] AttributedString succeeded")
            print("[renderMarkdown] Result length: \(nsAttrString.length)")
            print("[renderMarkdown] Result string: '\(nsAttrString.string)'")

            markdownTextView.attributedText = nsAttrString
            print("[renderMarkdown] Set markdownTextView.attributedText")
        } catch {
            print("[renderMarkdown] AttributedString failed: \(error)")
            print("[renderMarkdown] Using fallback parser")
            let result = parseMarkdown(text)
            markdownTextView.attributedText = result
        }
    }
    
    // MARK: - AttributedString-based parser (presentation intents)
    private func createStyledAttributedString(from markdown: String) throws -> AttributedString {
        print("[createStyledAttributedString] called, len=\(markdown.count)")
        
        var output = try AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
        
        // Set base styling for the entire text
        var baseContainer = AttributeContainer()
        baseContainer.font = bodyFont()
        baseContainer.foregroundColor = UIColor.label
        output.mergeAttributes(baseContainer)
        
        // Process inline formatting (bold, italic, code)
        for run in output.runs {
            var container = AttributeContainer()
            
            // Check for inline presentation intents
            if let inlineIntent = run.inlinePresentationIntent {
                if inlineIntent.contains(.stronglyEmphasized) {
                    container.font = boldBodyFont()
                }
                if inlineIntent.contains(.emphasized) {
                    container.font = italicBodyFont()
                }
                if inlineIntent.contains(.code) {
                    container.font = codeFont()
                    container.backgroundColor = UIColor.systemGray5
                }
                if inlineIntent.contains(.strikethrough) {
                    container.strikethroughStyle = .single
                }
            }
            
            // Apply the inline formatting
            if container.font != nil || container.backgroundColor != nil || container.strikethroughStyle != nil {
                output[run.range].mergeAttributes(container)
            }
        }
        
        // Process block-level presentation intents (headers, lists, quotes)
        for run in output.runs {
            guard let intentAttribute = run.presentationIntent else { continue }
            
            var container = AttributeContainer()
            let paragraphStyle = NSMutableParagraphStyle()
            
            for component in intentAttribute.components {
                switch component.kind {
                case .header(level: let level):
                    paragraphStyle.paragraphSpacing = 16
                    paragraphStyle.paragraphSpacingBefore = 8
                    
                    switch level {
                    case 1:
                        container.font = headingFont(level: 1)
                        paragraphStyle.paragraphSpacing = 20
                    case 2:
                        container.font = headingFont(level: 2)
                        paragraphStyle.paragraphSpacing = 18
                    case 3:
                        container.font = headingFont(level: 3)
                        paragraphStyle.paragraphSpacing = 16
                    default:
                        container.font = headingFont(level: 4)
                        paragraphStyle.paragraphSpacing = 14
                    }
                    
                case .orderedList:
                    paragraphStyle.paragraphSpacing = 8
                    paragraphStyle.firstLineHeadIndent = 0
                    paragraphStyle.headIndent = 25
                    container.font = bodyFont()
                    
                case .unorderedList:
                    paragraphStyle.paragraphSpacing = 8
                    paragraphStyle.firstLineHeadIndent = 0
                    paragraphStyle.headIndent = 20
                    container.font = bodyFont()
                    
                case .listItem(ordinal: let ordinalValue):
                    // For ordered lists, add the number
                    if ordinalValue != nil {
                        // This is an ordered list item
                        paragraphStyle.firstLineHeadIndent = 0
                        paragraphStyle.headIndent = 25
                    } else {
                        // This is an unordered list item
                        paragraphStyle.firstLineHeadIndent = 0
                        paragraphStyle.headIndent = 20
                    }
                    paragraphStyle.paragraphSpacing = 4
                    
                case .blockQuote:
                    container.backgroundColor = UIColor.systemGray5
                    container.foregroundColor = UIColor.secondaryLabel
                    paragraphStyle.firstLineHeadIndent = 20
                    paragraphStyle.headIndent = 20
                    paragraphStyle.paragraphSpacing = 12
                    
                case .codeBlock:
                    container.font = codeFont()
                    container.backgroundColor = UIColor.systemGray6
                    paragraphStyle.paragraphSpacing = 12
                    
                case .paragraph:
                    paragraphStyle.paragraphSpacing = 8
                    paragraphStyle.lineSpacing = 4
                    
                default:
                    break
                }
            }
            
            // Apply paragraph style if configured
            if paragraphStyle.paragraphSpacing > 0 || paragraphStyle.headIndent > 0 {
                container.paragraphStyle = paragraphStyle
            }
            
            // Apply the container attributes to the run
            if container.font != nil || container.backgroundColor != nil || container.foregroundColor != nil || container.paragraphStyle != nil {
                output[run.range].mergeAttributes(container, mergePolicy: .keepCurrent)
            }
        }
        
        return output
    }
    
    // MARK: - Fallback parser (NSAttributedString)
    private func parseMarkdown(_ text: String) -> NSAttributedString {
        print("[parseMarkdown] called, len=\(text.count)")
        let lines = text.components(separatedBy: .newlines)
        let result = NSMutableAttributedString()
        
        var previousWasEmpty = false
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Handle empty lines
            if trimmedLine.isEmpty {
                // Only add one newline for consecutive empty lines
                if !previousWasEmpty && index > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }
                previousWasEmpty = true
                continue
            }
            
            previousWasEmpty = false
            
            // Process the line content
            let block = processLine(line)
            
            // Add spacing before block elements (except at the beginning)
            if index > 0 && !result.string.hasSuffix("\n\n") {
                // Check if this is a block element that needs extra spacing
                if trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix(">") {
                    if !result.string.hasSuffix("\n") {
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
            }
            
            // Append the content block
            result.append(block)
            
            // Add newline after content (except for the last line)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        applyLinks(result)
        
        return result
    }
    
    // MARK: - Process a single line into a styled block
    private func processLine(_ line: String) -> NSAttributedString {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // Return empty string for empty lines
        if trimmedLine.isEmpty {
            return NSAttributedString(string: "")
        }
        
        // Headings
        if trimmedLine.hasPrefix("# ") {
            let headerText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let processedText = processInlineFormatting(headerText)
            let mutable = NSMutableAttributedString(attributedString: processedText)
            mutable.addAttributes([
                .font: headingFont(level: 1),
                .foregroundColor: UIColor.label,
                .paragraphStyle: makeParagraphStyle(spacing: 20)
            ], range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        
        if trimmedLine.hasPrefix("## ") {
            let headerText = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let processedText = processInlineFormatting(headerText)
            let mutable = NSMutableAttributedString(attributedString: processedText)
            mutable.addAttributes([
                .font: headingFont(level: 2),
                .foregroundColor: UIColor.label,
                .paragraphStyle: makeParagraphStyle(spacing: 16)
            ], range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        
        if trimmedLine.hasPrefix("### ") {
            let headerText = String(trimmedLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let processedText = processInlineFormatting(headerText)
            let mutable = NSMutableAttributedString(attributedString: processedText)
            mutable.addAttributes([
                .font: headingFont(level: 3),
                .foregroundColor: UIColor.label,
                .paragraphStyle: makeParagraphStyle(spacing: 14)
            ], range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        
        // Unordered list "- "
        if trimmedLine.hasPrefix("- ") {
            let listText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let bulletAttr: [NSAttributedString.Key: Any] = [
                .font: bodyFont(),
                .foregroundColor: UIColor.label
            ]
            let bulletString = NSMutableAttributedString(string: "• ", attributes: bulletAttr)
            let processedText = processInlineFormatting(listText)
            bulletString.append(processedText)
            
            // Add list paragraph style
            let listStyle = makeParagraphStyle(spacing: 6)
            listStyle.firstLineHeadIndent = 0
            listStyle.headIndent = 20 // Indent wrapped lines
            bulletString.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: 0, length: bulletString.length))
            
            return bulletString
        }
        
        // Blockquote
        if trimmedLine.hasPrefix("> ") {
            let quoteText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let processed = processInlineFormatting(quoteText)
            let mutable = NSMutableAttributedString(attributedString: processed)
            
            let quoteStyle = makeParagraphStyle(spacing: 12)
            quoteStyle.firstLineHeadIndent = 20
            quoteStyle.headIndent = 20
            
            mutable.addAttributes([
                .backgroundColor: UIColor.systemGray5,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: quoteStyle
            ], range: NSRange(location: 0, length: mutable.length))
            return mutable
        }
        
        // Ordered list "1. " etc.
        if let match = trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            let prefixText = String(trimmedLine[match])
            let afterIdx = match.upperBound
            let content = String(trimmedLine[afterIdx...]).trimmingCharacters(in: .whitespaces)
            
            let itemAttr: [NSAttributedString.Key: Any] = [
                .font: bodyFont(),
                .foregroundColor: UIColor.label
            ]
            let lineAttr = NSMutableAttributedString(string: prefixText, attributes: itemAttr)
            lineAttr.append(processInlineFormatting(content))
            
            // Add list paragraph style
            let listStyle = makeParagraphStyle(spacing: 6)
            listStyle.firstLineHeadIndent = 0
            listStyle.headIndent = 25 // Indent wrapped lines
            lineAttr.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: 0, length: lineAttr.length))
            
            return lineAttr
        }
        
        // Regular paragraph
        let paraProcessed = processInlineFormatting(trimmedLine)
        let mutablePara = NSMutableAttributedString(attributedString: paraProcessed)

        // IMPORTANT: Don't add .font here - it would overwrite bold fonts from processInlineFormatting!
        // Only add paragraphStyle and foregroundColor
        mutablePara.addAttributes([
            .paragraphStyle: makeParagraphStyle(spacing: 8),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: mutablePara.length))
        return mutablePara
    }
    
    // MARK: - Inline formatting (bold, italic, strikethrough)
    private func processInlineFormatting(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)

        // Base font
        result.addAttributes([
            .font: bodyFont(),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: result.length))

        // Process in order: Bold first, then strikethrough, then italic
        // This prevents conflicts between ** and *

        // 1. Bold: **text**
        processPatternSimple(pattern: "\\*\\*(.+?)\\*\\*", in: result) { content in
            let boldText = NSMutableAttributedString(string: content)
            boldText.addAttribute(.font, value: boldBodyFont(), range: NSRange(location: 0, length: content.count))
            return boldText
        }

        // 2. Underline: <u>text</u>
        processPatternSimple(pattern: "<u>(.+?)</u>", in: result) { content in
            let underlineText = NSMutableAttributedString(string: content)
            underlineText.addAttributes([
                .font: bodyFont(),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: UIColor.label
            ], range: NSRange(location: 0, length: content.count))
            return underlineText
        }

        // 3. Strikethrough: ~~text~~
        processPatternSimple(pattern: "~~(.+?)~~", in: result) { content in
            let strikeText = NSMutableAttributedString(string: content)
            strikeText.addAttributes([
                .font: bodyFont(),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: UIColor.label
            ], range: NSRange(location: 0, length: content.count))
            return strikeText
        }

        // 4. Italic: *text* or _text_
        processPatternSimple(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", in: result) { content in
            let italicText = NSMutableAttributedString(string: content)
            italicText.addAttribute(.font, value: italicBodyFont(), range: NSRange(location: 0, length: content.count))
            return italicText
        }

        processPatternSimple(pattern: "_(.+?)_", in: result) { content in
            let italicText = NSMutableAttributedString(string: content)
            italicText.addAttribute(.font, value: italicBodyFont(), range: NSRange(location: 0, length: content.count))
            return italicText
        }

        return result
    }

    // Helper function for pattern processing
    private func processPatternSimple(pattern: String, in attributedString: NSMutableAttributedString, transform: (String) -> NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return
        }

        let string = attributedString.string
        let range = NSRange(location: 0, length: string.utf16.count)
        let matches = regex.matches(in: string, options: [], range: range)

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let fullRange = match.range(at: 0)  // Full match including markers
                let contentRange = match.range(at: 1)  // Just the text inside

                let contentText = (string as NSString).substring(with: contentRange)
                let styledText = transform(contentText)

                // Replace full match with styled text (without markers)
                attributedString.replaceCharacters(in: fullRange, with: styledText)
            }
        }
    }
    
    // MARK: - Pattern processor
    private func processPattern(pattern: String, in attributedString: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any], removeMarkers: Bool = true) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("[processPattern] Failed to create regex for pattern: \(pattern)")
            return
        }
        let string = attributedString.string
        let range = NSRange(location: 0, length: string.utf16.count)
        let matches = regex.matches(in: string, options: [], range: range)

        print("[processPattern] Pattern: \(pattern), found \(matches.count) matches in: '\(string)'")

        // Process matches in reverse order to maintain string indices
        for (index, match) in matches.reversed().enumerated() {
            guard match.numberOfRanges >= 2 else {
                print("[processPattern] Match \(index) has insufficient ranges: \(match.numberOfRanges)")
                continue
            }

            let fullRange = match.range(at: 0)
            let fullMatch = (string as NSString).substring(with: fullRange)
            print("[processPattern] Match \(index): fullRange=\(fullRange), fullMatch='\(fullMatch)'")

            // Find the first non-empty capture group (for patterns with alternatives like italic)
            var contentRange = NSRange(location: NSNotFound, length: 0)
            for i in 1..<match.numberOfRanges {
                let range = match.range(at: i)
                if range.location != NSNotFound {
                    contentRange = range
                    let content = (string as NSString).substring(with: range)
                    print("[processPattern] Match \(index): Found capture group \(i) at \(range): '\(content)'")
                    break
                }
            }

            guard contentRange.location != NSNotFound else {
                print("[processPattern] Match \(index): No valid capture group found")
                continue
            }

            if removeMarkers {
                // Extract the content
                let content = (string as NSString).substring(with: contentRange)
                print("[processPattern] Match \(index): Extracting content '\(content)' from range \(contentRange)")
                let styledContent = NSMutableAttributedString(string: content)

                // Apply the attributes
                styledContent.addAttributes(attributes, range: NSRange(location: 0, length: content.count))

                // Replace the full match with styled content
                print("[processPattern] Match \(index): Replacing fullRange \(fullRange) with styled content")
                attributedString.replaceCharacters(in: fullRange, with: styledContent)
            } else {
                // Just apply attributes without removing markers
                print("[processPattern] Match \(index): Applying attributes to contentRange \(contentRange) without removing markers")
                attributedString.addAttributes(attributes, range: contentRange)
            }
        }

        print("[processPattern] After processing, string is: '\(attributedString.string)'")
    }
    
    // MARK: - Paragraph style helper
    private func makeParagraphStyle(spacing: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = spacing
        return style
    }

    private func bodyFont() -> UIFont {
        UIFont.systemFont(ofSize: markdownFontSize)
    }

    private func boldBodyFont() -> UIFont {
        UIFont.boldSystemFont(ofSize: markdownFontSize)
    }

    private func italicBodyFont() -> UIFont {
        UIFont.italicSystemFont(ofSize: markdownFontSize)
    }

    private func codeFont() -> UIFont {
        UIFont.monospacedSystemFont(ofSize: max(markdownFontSize - 2, 11), weight: .regular)
    }

    private func monospacedBodyFont() -> UIFont {
        UIFont.monospacedSystemFont(ofSize: markdownFontSize, weight: .regular)
    }

    private func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        switch level {
        case 1:
            size = markdownFontSize * 2.375
        case 2:
            size = markdownFontSize * 1.75
        case 3:
            size = markdownFontSize * 1.375
        default:
            size = markdownFontSize * 1.125
        }
        return UIFont.boldSystemFont(ofSize: size)
    }

    // MARK: - UITextViewDelegate
    // No need for textViewDidChange - we edit in textView directly

    // MARK: - Custom Edit Menu
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        print("DEBUG editMenu: called for range \(range), textView==self.textView: \(textView == self.textView)")

        // Only show custom menu if text is selected
        guard range.length > 0 else {
            return UIMenu(children: suggestedActions)
        }

        // Determine which textView triggered this (though we now mainly use markdownTextView)
        let activeTextView = textView

        // Create custom markdown formatting actions
        // Use selectedRange at action time, not the range parameter
        let boldAction = UIAction(title: "Bold".localized, image: UIImage(systemName: "bold")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .bold, to: currentRange, in: activeTextView)
        }
        boldAction.attributes = []

        let italicAction = UIAction(title: "Italic".localized, image: UIImage(systemName: "italic")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .italic, to: currentRange, in: activeTextView)
        }

        let codeAction = UIAction(title: "Code".localized, image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .code, to: currentRange, in: activeTextView)
        }

        let strikethroughAction = UIAction(title: "Strikethrough".localized, image: UIImage(systemName: "strikethrough")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .strikethrough, to: currentRange, in: activeTextView)
        }

        let underlineAction = UIAction(title: "Underline".localized, image: UIImage(systemName: "underline")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .underline, to: currentRange, in: activeTextView)
        }

        let headingAction = UIAction(title: "Heading".localized, image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .heading, to: currentRange, in: activeTextView)
        }

        let linkAction = UIAction(title: "Link".localized, image: UIImage(systemName: "link")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .link, to: currentRange, in: activeTextView)
        }

        let bulletAction = UIAction(title: "Bullet List".localized, image: UIImage(systemName: "list.bullet")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.applyMarkdownToActiveView(type: .bullet, to: currentRange, in: activeTextView)
        }

        let replaceAction = UIAction(title: "Replace", image: UIImage(systemName: "arrow.left.arrow.right")) { [weak self] _ in
            guard let self = self else { return }
            let currentRange = activeTextView.selectedRange
            self.showReplacePopover(for: activeTextView, range: currentRange)
        }

        // Create markdown submenu
        let markdownMenu = UIMenu(title: "Markdown", image: UIImage(systemName: "textformat"), children: [
            boldAction,
            italicAction,
            underlineAction,
            codeAction,
            strikethroughAction,
            headingAction,
            linkAction,
            bulletAction
        ])

        // Combine with suggested actions and replace action
        return UIMenu(children: [markdownMenu, replaceAction] + suggestedActions)
    }

    // Apply markdown formatting - works in BOTH edit and preview mode!
    private func applyMarkdownToActiveView(type: MarkdownType, to range: NSRange, in activeTextView: UITextView) {
        print("DEBUG applyMarkdown: type=\(type)")
        print("DEBUG applyMarkdown: activeTextView==textView: \(activeTextView == textView)")
        print("DEBUG applyMarkdown: activeTextView==markdownTextView: \(activeTextView == markdownTextView)")

        // Get the raw markdown text
        guard let rawMarkdown = textView.text else {
            print("DEBUG applyMarkdown: No raw markdown text!")
            return
        }

        // Get selected text from whichever view is active
        let selectedText: String
        if activeTextView == markdownTextView {
            // PREVIEW MODE - Get selected text from rendered view
            guard let attributedText = markdownTextView.attributedText else { return }
            selectedText = (attributedText.string as NSString).substring(with: range)
            print("DEBUG applyMarkdown: Preview mode - selected: '\(selectedText)'")
        } else {
            // EDIT MODE - Get selected text from raw markdown
            selectedText = (rawMarkdown as NSString).substring(with: range)
            print("DEBUG applyMarkdown: Edit mode - selected: '\(selectedText)'")
        }

        // Build markdown wrapper based on type
        var replacement = ""

        switch type {
        case .bold:
            replacement = "**\(selectedText)**"
        case .italic:
            replacement = "*\(selectedText)*"
        case .underline:
            replacement = "<u>\(selectedText)</u>"
        case .code:
            replacement = "`\(selectedText)`"
        case .strikethrough:
            replacement = "~~\(selectedText)~~"
        case .heading:
            replacement = "## \(selectedText)"
        case .link:
            replacement = "[\(selectedText)](url)"
        case .bullet:
            let lines = selectedText.components(separatedBy: .newlines)
            let bulletLines = lines.map { line in
                line.trimmingCharacters(in: .whitespaces).isEmpty ? line : "- \(line)"
            }
            replacement = bulletLines.joined(separator: "\n")
        }

        print("DEBUG applyMarkdown: Will wrap '\(selectedText)' as: '\(replacement)'")

        // Find selectedText in raw markdown and replace it
        // Simple approach: Find first occurrence of selectedText in rawMarkdown
        if let rangeInRaw = rawMarkdown.range(of: selectedText) {
            let newMarkdown = rawMarkdown.replacingCharacters(in: rangeInRaw, with: replacement)
            print("DEBUG applyMarkdown: Updated raw markdown length: \(newMarkdown.count)")

            // Update raw markdown
            textView.text = newMarkdown

            // If in preview mode, re-render
            if activeTextView == markdownTextView {
                print("DEBUG applyMarkdown: Re-rendering preview after edit")
                renderMarkdown()
                // Stay in preview mode!
            }
        } else {
            print("DEBUG applyMarkdown: Could not find '\(selectedText)' in raw markdown!")
        }
    }

    // MARK: - Replace Text Popover
    private func showReplacePopover(for textView: UITextView, range: NSRange) {
        // Get selected text and calculate raw markdown range
        let selectedText: String
        let rawMarkdownRange: NSRange

        if textView == markdownTextView {
            // Preview mode - get from rendered text
            guard let attributedText = markdownTextView.attributedText else { return }
            selectedText = (attributedText.string as NSString).substring(with: range)

            // Calculate the corresponding range in raw markdown
            // We need to find where this text appears in the raw markdown
            guard let rawText = self.textView.text else { return }

            // Try to find the exact text first
            if let foundRange = rawText.range(of: selectedText, options: .literal) {
                rawMarkdownRange = NSRange(foundRange, in: rawText)
                print("DEBUG showReplacePopover: Found exact match in raw at \(rawMarkdownRange)")
            } else {
                // If exact match fails, we need to map character positions
                // This is complex - use a simpler approach: switch to edit mode temporarily
                print("DEBUG showReplacePopover: No exact match, cannot map positions reliably")
                print("DEBUG showReplacePopover: Consider switching to edit mode for this operation")

                // Show alert to user
                let alert = UIAlertController(
                    title: "Replace in preview mode",
                    message: "To replace formatted text, switch to edit mode first (tap the pencil icon).",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
        } else {
            // Edit mode - get from raw markdown
            guard let rawText = self.textView.text else { return }
            selectedText = (rawText as NSString).substring(with: range)
            rawMarkdownRange = range
        }

        // Create replace text view controller
        let replaceVC = ReplaceTextViewController()
        replaceVC.originalText = selectedText
        replaceVC.onReplace = { [weak self] newText in
            self?.replaceTextDirect(range: rawMarkdownRange, with: newText)
        }

        // Present as sheet
        if let sheet = replaceVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        present(replaceVC, animated: true)
    }

    // Simple direct replacement using the pre-calculated range
    private func replaceTextDirect(range: NSRange, with newText: String) {
        print("DEBUG replaceTextDirect: range: \(range), newText length: \(newText.count)")

        guard let rawMarkdown = textView.text else {
            print("DEBUG replaceTextDirect: No raw markdown!")
            return
        }

        // Validate range
        let nsString = rawMarkdown as NSString
        guard range.location + range.length <= nsString.length else {
            print("DEBUG replaceTextDirect: Invalid range!")
            return
        }

        // Extract what we're replacing (for debugging)
        let replacedText = nsString.substring(with: range)
        print("DEBUG replaceTextDirect: Replacing '\(replacedText)' with '\(newText)'")

        // Perform replacement
        let updatedMarkdown = nsString.replacingCharacters(in: range, with: newText)
        textView.text = updatedMarkdown

        // Re-render if we're in preview mode
        if !textView.isHidden {
            print("DEBUG replaceTextDirect: Edit mode - no need to re-render")
        } else {
            print("DEBUG replaceTextDirect: Preview mode - re-rendering")
            renderMarkdown()
        }
    }

    // MARK: - Markdown Formatting Helpers
    enum MarkdownType {
        case bold, italic, underline, code, strikethrough, heading, link, bullet
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate
extension MarkdownViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        // Called when user dismisses by gesture (swipe down, etc.)
        // Ensure data is saved before dismissal
        saveIfNeeded()
    }
}

// MARK: - Replace Text View Controller
class ReplaceTextViewController: UIViewController {
    var originalText: String = ""
    var onReplace: ((String) -> Void)?

    private let textView = UITextView()
    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let replaceButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupUI()
        textView.text = originalText

        // Auto-focus and select all
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: 0, length: originalText.count)
    }

    private func setupUI() {
        // Title label
        titleLabel.text = "Replace text"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 20)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // TextView with border
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Replace button
        replaceButton.setTitle("Replace", for: .normal)
        replaceButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        replaceButton.addTarget(self, action: #selector(replaceTapped), for: .touchUpInside)
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(replaceButton)

        // Layout
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // TextView
            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textView.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -20),

            // Buttons
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            replaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            replaceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            replaceButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),
            replaceButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func replaceTapped() {
        let newText = textView.text ?? ""
        onReplace?(newText)
        dismiss(animated: true)
    }
}

extension UITextView {
    func addDoneToolbar(target: Any, doneAction: Selector, pasteAction: Selector?) {
        let tb = UIToolbar()
        tb.sizeToFit()

        var items: [UIBarButtonItem] = []

        // Sjekk om det er noe i clipboard
        if let pasteAction = pasteAction, UIPasteboard.general.hasStrings {
            // Vis både Paste og Done knapper
            let pasteButton = UIBarButtonItem(
                title: "Lim inn",
                style: .plain,
                target: target,
                action: pasteAction
            )
            items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                pasteButton,
                UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil).apply { $0.width = 20 },
                UIBarButtonItem(barButtonSystemItem: .done, target: target, action: doneAction)
            ]
        } else {
            // Vis bare Done knapp
            items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .done, target: target, action: doneAction)
            ]
        }

        tb.items = items
        inputAccessoryView = tb
    }
}

extension UIBarButtonItem {
    func apply(_ closure: (UIBarButtonItem) -> Void) -> UIBarButtonItem {
        closure(self)
        return self
    }
}

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
