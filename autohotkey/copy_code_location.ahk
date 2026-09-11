#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut

if A_Args.Length && A_Args[1] = "--self-test" {
    RunSelfTests()
    ExitApp(0)
}

; The $ prefix forces the keyboard hook. Rider can otherwise consume this chord
; before a context-sensitive AutoHotkey hotkey sees it.
$^!c::HandleCopyLocationHotkey()

HandleCopyLocationHotkey() {
    editor := GetActiveEditor()
    if !editor {
        ; Preserve Ctrl+Alt+C for applications outside the supported editors.
        SendEvent("^!c")
        return
    }
    CopyCodeLocation(editor)
}

CopyCodeLocation(editor) {

    ; Release the triggering modifiers before sending the IDE shortcuts below.
    KeyWait("c")
    KeyWait("Alt")
    KeyWait("Ctrl")
    Sleep(80)

    savedClipboard := ClipboardAll()

    selectedText := CopyCurrentSelection(editor)
    if selectedText = "" {
        A_Clipboard := savedClipboard
        ShowError("请先在 Rider 或 VS Code 中选中一些文字。")
        return
    }

    filePath := CopyActiveFilePath(editor)
    if !IsAbsoluteWindowsPath(filePath) {
        A_Clipboard := savedClipboard
        if editor = "vscode"
            ShowError("无法取得当前文件的绝对路径。请确认 VS Code 当前焦点位于文本编辑区。")
        else
            ShowError("无法取得当前文件的绝对路径。请确认 Rider 的 Ctrl+Shift+C 快捷键仍为默认设置。")
        return
    }

    if editor = "rider" {
        caret := ReadRiderCaretPosition()
        if !caret {
            A_Clipboard := savedClipboard
            ShowError("无法读取 Rider 当前的行列位置。")
            return
        }
        start := InferSelectionStart(caret, selectedText, filePath)
    } else {
        ; VS Code does not expose its caret position through a stable dialog, so
        ; keep its existing navigation-based calculation and restore afterward.
        SendEditorKeys(editor, "{Left}")
        Sleep(50)
        prefix := CopyFromDocumentStart(editor)
        start := PositionAfterText(prefix)
        RestoreOriginalSelection(editor, prefix, selectedText)
    }
    rangeText := FormatRange(start, selectedText)
    result := "File: " . GetFileName(filePath) . "`r`n" . rangeText . "`r`n`r`n"

    if !PutClipboard(result) {
        A_Clipboard := savedClipboard
        ShowError("系统剪贴板写入失败，请重试。")
        return
    }

    MsgBox("已复制到剪贴板：`n`n" . result, "复制代码位置", "Iconi")
}

GetActiveEditor() {
    processName := StrLower(WinGetProcessName("A"))
    if processName = "rider64.exe" || processName = "rider.exe"
        return "rider"
    if processName = "code.exe" || processName = "code-insiders.exe" || processName = "codium.exe"
        return "vscode"
    return ""
}

CopyCurrentSelection(editor) {
    A_Clipboard := ""
    SendEditorKeys(editor, "^c")
    return ClipWait(2) ? A_Clipboard : ""
}

CopyActiveFilePath(editor) {
    A_Clipboard := ""
    if editor = "vscode" {
        ; Invoke the built-in command through the command palette so VS Code does
        ; not need a custom keybinding. This installation uses the English UI.
        SendInput("{F1}")
        Sleep(300)
        SendText("File: Copy Path of Active File")
        Sleep(150)
        SendInput("{Enter}")
    } else {
        ; Rider/JetBrains: Copy Paths (absolute path in the default keymap).
        SendEvent("^+c")
    }

    if !ClipWait(3) {
        if editor = "vscode"
            SendInput("{Esc}")
        return ""
    }
    return Trim(A_Clipboard, " `t`r`n`"")
}

CopyFromDocumentStart(editor) {
    A_Clipboard := ""
    SendEditorKeys(editor, "^+{Home}")
    Sleep(100)
    SendEditorKeys(editor, "^c")
    if ClipWait(5)
        return A_Clipboard

    ; An empty prefix is valid when the selection starts at line 1, column 1.
    return ""
}

ReadRiderCaretPosition() {
    ; Rider's Go to Line/Column dialog is prefilled with the current caret as
    ; line:column. Closing it with Escape preserves both selection and viewport.
    positionText := ReadRiderPositionFromDialog("^g")
    if RegExMatch(positionText, "^\s*(\d+)\s*[:,]\s*(\d+)\s*$", &match)
        return { line: Integer(match[1]), column: Integer(match[2]) }

    ; IdeaVim and custom keymaps can consume Ctrl+G. Action Search invokes the
    ; same Rider action without changing any Rider settings or editor state.
    for query in ["Go to Line/Column", "转到行/列"] {
        positionText := ReadRiderPositionFromActionSearch(query)
        if RegExMatch(positionText, "^\s*(\d+)\s*[:,]\s*(\d+)\s*$", &match)
            return { line: Integer(match[1]), column: Integer(match[2]) }
    }
    return false
}

ReadRiderPositionFromDialog(trigger) {
    A_Clipboard := ""
    SendEvent(trigger)
    Sleep(300)
    if !IsRiderDialogActive()
        return ""

    SendEvent("^a")
    SendEvent("^c")
    positionText := ClipWait(1) ? A_Clipboard : ""
    SendEvent("{Esc}")
    return positionText
}

ReadRiderPositionFromActionSearch(query) {
    A_Clipboard := ""
    SendEvent("^+a")
    Sleep(300)
    if !IsRiderDialogActive()
        return ""

    SendText(query)
    Sleep(300)
    SendEvent("{Enter}")
    Sleep(300)
    if !IsRiderDialogActive() {
        SendEvent("{Esc}")
        return ""
    }

    SendEvent("^a")
    SendEvent("^c")
    positionText := ClipWait(1) ? A_Clipboard : ""
    SendEvent("{Esc}")
    return positionText
}

IsRiderDialogActive() {
    return WinGetClass("A") ~= "i)SunAwtDialog|#32770"
}

InferSelectionStart(caret, selectedText, filePath := "") {
    ; The caret is normally at the end of a forward selection. For a backward
    ; selection, compare the on-disk text around the caret when possible.
    if IsCaretAtSelectionStart(caret, selectedText, filePath)
        return caret

    selectedText := NormalizeNewlines(selectedText)
    newlineCount := StrLen(selectedText) - StrLen(StrReplace(selectedText, "`n"))
    if newlineCount = 0
        return { line: caret.line, column: Max(1, caret.column - StrLen(selectedText)) }
    return { line: Max(1, caret.line - newlineCount), column: 1 }
}

IsCaretAtSelectionStart(caret, selectedText, filePath) {
    if filePath = "" || !FileExist(filePath)
        return false

    try documentText := NormalizeNewlines(FileRead(filePath))
    catch
        return false

    selectedText := NormalizeNewlines(selectedText)
    selectionLength := StrLen(selectedText)
    caretIndex := TextIndexAtPosition(documentText, caret)
    if !caretIndex || selectionLength = 0
        return false

    startsAtCaret := SubStr(documentText, caretIndex, selectionLength) = selectedText
    selectionStartIndex := caretIndex - selectionLength
    endsAtCaret := selectionStartIndex >= 1
        && SubStr(documentText, selectionStartIndex, selectionLength) = selectedText
    return startsAtCaret && !endsAtCaret
}

TextIndexAtPosition(text, position) {
    lines := StrSplit(NormalizeNewlines(text), "`n")
    if position.line < 1 || position.line > lines.Length
        return 0
    if position.column < 1 || position.column > StrLen(lines[position.line]) + 1
        return 0

    index := position.column
    Loop position.line - 1
        index += StrLen(lines[A_Index]) + 1
    return index
}

RestoreOriginalSelection(editor, prefix, selectedText) {
    ; Ctrl+Shift+Home leaves the caret at document start and the anchor at the
    ; original selection start. Right collapses that temporary selection to the
    ; anchor, then Shift+Right recreates the original selected range.
    SendEditorKeys(editor, "{Right}")
    if prefix = ""
        SendEditorKeys(editor, "{Left}")

    moveCount := CountCaretMoves(selectedText)
    if moveCount > 0 {
        ; SendEvent applies a per-key delay in Rider, which makes restoration look
        ; like a long selection animation. SendInput batches the whole sequence.
        SendInput("{Shift down}{Right " . moveCount . "}{Shift up}")
        Sleep(50)
    }
}

CountCaretMoves(text) {
    text := NormalizeNewlines(text)
    count := 0
    pos := 1
    while pos := RegExMatch(text, "\X", &match, pos) {
        count += 1
        pos += StrLen(match[0])
    }
    return count
}

SendEditorKeys(editor, keys) {
    if editor = "vscode"
        SendInput(keys)
    else
        SendEvent(keys)
}

PositionAfterText(text) {
    text := NormalizeNewlines(text)
    lines := StrSplit(text, "`n")
    return { line: lines.Length, column: StrLen(lines[lines.Length]) + 1 }
}

FormatRange(start, selectedText) {
    selectedText := NormalizeNewlines(selectedText)
    newlineCount := StrLen(selectedText) - StrLen(StrReplace(selectedText, "`n"))

    if newlineCount = 0 {
        endColumn := start.column + StrLen(selectedText) - 1
        return "Line: " . start.line . " , Column : " . start.column . "-" . endColumn
    }

    ; A selection ending immediately after a newline does not include content from
    ; the following line, so report the last line that contains selected text.
    endLine := start.line + newlineCount
    if SubStr(selectedText, -1) = "`n"
        endLine -= 1
    return "Line: " . start.line . "-" . Max(start.line, endLine)
}

NormalizeNewlines(text) {
    return StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
}

IsAbsoluteWindowsPath(path) {
    return RegExMatch(path, "i)^(?:[a-z]:\\|\\\\).+")
}

GetFileName(path) {
    SplitPath(path, &fileName)
    return fileName
}

PutClipboard(text) {
    A_Clipboard := ""
    A_Clipboard := text
    return ClipWait(1) && A_Clipboard = text
}

ShowError(message) {
    MsgBox(message, "复制代码位置", "Icon!")
}

RunSelfTests() {
    start := PositionAfterText("first`r`nabc")
    Assert(start.line = 2 && start.column = 4, "position")
    Assert(FormatRange({ line: 24, column: 1 }, "0123456789")
        = "Line: 24 , Column : 1-10", "single line")
    Assert(FormatRange({ line: 24, column: 3 }, "a`r`nb`r`nc")
        = "Line: 24-26", "multiple lines")
    Assert(FormatRange({ line: 24, column: 1 }, "a`r`nb`r`n")
        = "Line: 24-25", "trailing newline")
    Assert(IsAbsoluteWindowsPath("D:\path\to\File.java"), "drive path")
    Assert(IsAbsoluteWindowsPath("\\server\share\File.java"), "UNC path")
    Assert(GetFileName("D:\path\to\File.java") = "File.java", "file name")
    Assert(CountCaretMoves("a`r`nb") = 3, "caret moves for newline")
    Assert(CountCaretMoves("A😀B") = 3, "caret moves for surrogate pair")
    forwardStart := InferSelectionStart({ line: 24, column: 11 }, "0123456789")
    Assert(forwardStart.line = 24 && forwardStart.column = 1, "forward selection start")
    Assert(TextIndexAtPosition("one`ntwo`nthree", { line: 2, column: 2 }) = 6,
        "text index at position")
}

Assert(condition, testName) {
    if !condition {
        FileAppend("Self-test failed: " . testName . "`n", "**")
        ExitApp(1)
    }
}
