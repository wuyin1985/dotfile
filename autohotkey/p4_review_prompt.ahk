#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut

SetTitleMatchMode 2

if A_Args.Length && A_Args[1] = "--self-test" {
    selfTestIds := ExtractChangeIds("3696177 user 2026/09/02`nChange 3696178")
    if selfTestIds.Length != 2 || selfTestIds[1] != "3696177" || selfTestIds[2] != "3696178"
        ExitApp(1)
    bareIds := ExtractChangeIds("[3696177]")
    if bareIds.Length != 1 || bareIds[1] != "3696177"
        ExitApp(2)
    decoratedIds := ExtractChangeIds("Pending: 3696177 (updated 2026/09/02)")
    if decoratedIds.Length != 1 || decoratedIds[1] != "3696177"
        ExitApp(3)
    savedTestClipboard := ClipboardAll()
    if !PutClipboard("review p4 changelist 3696177") || A_Clipboard != "review p4 changelist 3696177" {
        A_Clipboard := savedTestClipboard
        ExitApp(4)
    }
    A_Clipboard := savedTestClipboard
    ExitApp(0)
}

; Ctrl+Alt+R generates a review prompt from the selected P4V changelists.
^!r::GenerateReviewPrompt()

GenerateReviewPrompt() {
    if !WinActive("ahk_exe p4v.exe") {
        MsgBox("请先在 P4V 中选中一个或多个 pending changelist。", "P4V Review", "Icon!")
        return
    }

    ; Do not let the hotkey's Ctrl+Alt modifiers turn the copy into Ctrl+Alt+C.
    KeyWait("r")
    KeyWait("Alt")
    KeyWait("Ctrl")
    Sleep(80)

    savedClipboard := ClipboardAll()
    A_Clipboard := ""
    ; Qt views can update the clipboard asynchronously, especially for one selected row.
    SendEvent("^c")
    if !ClipWait(3) {
        Sleep(150)
        SendEvent("^c")
        ClipWait(2)
    }
    if !A_Clipboard {
        ; Some Qt item views expose copy as the legacy Ctrl+Insert shortcut.
        SendEvent("^Insert")
        ClipWait(2)
    }
    if !A_Clipboard {
        A_Clipboard := savedClipboard
        MsgBox("无法读取 P4V 当前选择，请先选中 changelist 后重试。", "P4V Review", "Icon!")
        return
    }

    selectedText := A_Clipboard
    changeIds := ExtractChangeIds(selectedText)
    if changeIds.Length = 0 {
        A_Clipboard := savedClipboard
        MsgBox("未从 P4V 当前选择中找到 changelist 编号。", "P4V Review", "Icon!")
        return
    }

    prompt := "review p4 changelist " . Join(changeIds, ", ")
    if !PutClipboard(prompt) {
        A_Clipboard := savedClipboard
        MsgBox("系统剪切板写入失败，请重试或手动复制：`n" . prompt, "P4V Review", "Icon!")
        return
    }
    MsgBox("该字符串已经复制到剪切板：`n" . prompt, "P4V Review", "Iconi")
}

PutClipboard(text) {
    A_Clipboard := ""
    A_Clipboard := text
    if ClipWait(0.5) && A_Clipboard = text
        return true
    ; Retry through the legacy Clipboard alias used by older AHK v2 builds.
    Clipboard := text
    return ClipWait(0.5) && A_Clipboard = text
}

ExtractChangeIds(text) {
    ids := []
    seen := Map()

    ; Prefer explicit labels when P4V includes them in copied rows.
    pos := 1
    while pos := RegExMatch(text, "i)(?:change(?:list)?|cl)\s*#?\s*(\d{3,})\b", &match, pos) {
        AddUnique(ids, seen, match[1])
        pos += StrLen(match[0])
    }

    ; Pending changelist tables commonly copy one row as: 3696177 <user> <date> ...
    for line in StrSplit(text, "`n", "`r") {
        if RegExMatch(line, "^\s*(\d{3,})(?:\s+|$)", &rowMatch)
            AddUnique(ids, seen, rowMatch[1])
    }

    ; Some P4V single-row copies contain only a number in brackets or a decorated cell.
    ; Changelists in this depot are six or more digits; this avoids dates/revisions.
    if ids.Length = 0 {
        pos := 1
        while pos := RegExMatch(text, "\b(\d{6,})\b", &fallbackMatch, pos) {
            AddUnique(ids, seen, fallbackMatch[1])
            pos += StrLen(fallbackMatch[0])
        }
    }
    return ids
}

AddUnique(ids, seen, value) {
    if !seen.Has(value) {
        seen[value] := true
        ids.Push(value)
    }
}

Join(values, separator) {
    result := ""
    for index, value in values
        result .= (index = 1 ? "" : separator) . value
    return result
}
