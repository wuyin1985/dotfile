#Requires AutoHotkey v2.0
#SingleInstance Force

startupLink := A_Startup "\startup.ahk.lnk"
EnsureStartupShortcut(startupLink)

Loop Files, A_ScriptDir "\*.ahk", "F" {
    if StrLower(A_LoopFileFullPath) = StrLower(A_ScriptFullPath)
        continue

    try Run('"' A_AhkPath '" "' A_LoopFileFullPath '"', A_ScriptDir)
}

EnsureStartupShortcut(linkFile) {
    try FileCreateShortcut(
        A_AhkPath,
        linkFile,
        A_ScriptDir,
        '"' A_ScriptFullPath '"',
        "Load all AutoHotkey scripts in this folder"
    )
}
