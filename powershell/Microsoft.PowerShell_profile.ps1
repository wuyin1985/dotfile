set-psreadlinekeyhandler -key tab -function complete
$env:shell = "wt.exe"

import-module psreadline
import-module psfzf

set-psreadlineoption -predictionsource history
set-psreadlineoption -predictionviewstyle listview
Set-PSReadlineOption -EditMode vi
Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete

invoke-expression (& {
    $hook = if ($psversiontable.psversion.major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell | out-string)
})



function ccd() {

    # 构建参数：默认添加 -path 当前目录，若用户手动指定了 -path 则覆盖
    $arguments = @()
    $hasPath = $false

    # 检查用户是否传入了 -path 或 --path 参数
    foreach ($arg in $args) {
        if ($arg -eq "-path" -or $arg -eq "--path") {
            $hasPath = $true
            break
        }
    }

    # 若用户未指定 -path，则默认添加当前目录
    if (-not $hasPath) {
        $currentDir = (Get-Location).Path
        $arguments += "-path", "`"$currentDir`""  # 处理路径中的空格
    }

    # 添加用户传入的所有参数（会覆盖默认的 -path 若用户指定了）
    $arguments += $args

    &es.exe $arguments -sort-date-modified-descending -name -dm -size | invoke-fzf | % {if ((get-item $_) -is [system.io.directoryinfo]) {cd $_} else {cd (split-path -path $_)}}
}


function ccdg() {
    write-host $args
    &es.exe $args | invoke-fzf | % {if ((get-item $_) -is [system.io.directoryinfo]) {cd $_} else {cd (split-path -path $_)}}
}


function y {
    $tmp = (New-TemporaryFile).FullName
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
        Set-Location -LiteralPath (Resolve-Path -LiteralPath $cwd).Path
    }
    Remove-Item -Path $tmp
}


function OnViModeChange {
    if ($args[0] -eq 'Command') {
        # Set the cursor to a blinking block.
        Write-Host -NoNewline "`e[1 q"
    } else {
        # Set the cursor to a blinking line.
        Write-Host -NoNewline "`e[5 q"
    }
}

Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange

$script:ExplorerFolderCycleIndex = -1
$script:ExplorerFolderOrderSeed = 0
$script:ExplorerFolderOrderMap = @{}

function Get-OpenExplorerFolders {
    $shell = $null

    try {
        $shell = New-Object -ComObject Shell.Application
    }
    catch {
        return @()
    }

    $folders = @()

    foreach ($window in @($shell.Windows())) {
        try {
            if (-not $window) { continue }

            $document = $window.Document
            if (-not $document) { continue }

            $folder = $document.Folder
            if (-not $folder) { continue }

            $path = $folder.Self.Path
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }

            $resolvedPath = (Resolve-Path -LiteralPath $path).Path
            $windowId = [string]$window.HWND

            if (-not $script:ExplorerFolderOrderMap.ContainsKey($windowId)) {
                $script:ExplorerFolderOrderSeed += 1
                $script:ExplorerFolderOrderMap[$windowId] = $script:ExplorerFolderOrderSeed
            }

            $folders += [pscustomobject]@{
                Hwnd  = $windowId
                Path  = $resolvedPath
                Order = $script:ExplorerFolderOrderMap[$windowId]
            }
        }
        catch {
            continue
        }
    }

    $activeWindowIds = @($folders | ForEach-Object { $_.Hwnd })
    foreach ($knownWindowId in @($script:ExplorerFolderOrderMap.Keys)) {
        if ($knownWindowId -notin $activeWindowIds) {
            $script:ExplorerFolderOrderMap.Remove($knownWindowId)
        }
    }

    return @(
        $folders |
            Sort-Object Order, Path |
            Group-Object Hwnd |
            ForEach-Object { $_.Group[0] }
    )
}

function Switch-ToNextExplorerFolder {
    $folders = @(Get-OpenExplorerFolders)

    if ($folders.Count -eq 0) {
        Write-Host "未找到已打开的资源管理器目录。" -ForegroundColor Yellow
        return
    }

    $script:ExplorerFolderCycleIndex = ($script:ExplorerFolderCycleIndex + 1) % $folders.Count
    $targetFolder = $folders[$script:ExplorerFolderCycleIndex].Path

    Set-Location -LiteralPath $targetFolder
    Write-Host "已切换到: $targetFolder" -ForegroundColor Cyan
}

$ExplorerFolderCycleKeyHandler = {
    param($key, $arg)

    Switch-ToNextExplorerFolder
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
    # 注意：Alt+Shift+字母在 Windows/Windows Terminal/输入法下不稳定，常会被折叠成 Alt+字母，
    # 甚至被系统语言切换快捷键拦截，因此这里显式绑定更稳定的组合键。
    Set-PSReadLineKeyHandler -Chord 'Alt+t' -BriefDescription 'ExplorerFolderCycle' -LongDescription '切换到已打开的资源管理器目录' -ScriptBlock $ExplorerFolderCycleKeyHandler
    Set-PSReadLineKeyHandler -Chord 'Ctrl+Alt+t' -BriefDescription 'ExplorerFolderCycle' -LongDescription '切换到已打开的资源管理器目录' -ScriptBlock $ExplorerFolderCycleKeyHandler
}

function oos {
    & "E:\work\xgame_p4\Tools\OutOfSyncLogAnalysis\bin\OutOfSyncLogAnalysis.exe" 'f:\outofsync' @args
}

function bc {
    & 'C:\Program Files\Beyond compare 5\BComp.exe' @args
}

function bcc {
    $clip = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    if (-not $clip) { $clip = Get-Clipboard -ErrorAction SilentlyContinue }

    $lines = @()
    if ($clip -is [string]) {
        $lines = $clip -split "`r?`n"
    } else {
        $lines = @($clip)
    }

    $lines = $lines | Where-Object { $_ -and $_.Trim().Length -gt 0 }
    & 'C:\Program Files\Beyond compare 5\BComp.exe' $lines[0] $lines[1]
}

function q { exit }


function svnc {
    <#
    .SYNOPSIS
    使用TortoiseSVN提交指定目录到SVN仓库
    
    .DESCRIPTION
    调用TortoiseProc.exe，打开SVN提交对话框，对指定目录进行提交操作
    
    .PARAMETER Path
    需要提交的目录路径，默认为当前目录
    
    .EXAMPLE
    Commit-Svn
    提交当前目录到SVN
    
    .EXAMPLE
    Commit-Svn -Path "D:\projects\myapp"
    提交D:\projects\myapp目录到SVN
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Path = (Get-Location).Path
    )
    
    # 检查路径是否存在
    if (-not (Test-Path -Path $Path)) {
        Write-Error "指定的路径不存在: $Path"
        return
    }
    
    # 检查路径是否为目录
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "指定的路径不是目录: $Path"
        return
    }
   
    # 调用TortoiseProc执行提交操作
    # 命令参数说明:
    # /command:commit - 提交操作
    # /path:$Path - 要提交的目录
    # /notempfile - 不使用临时文件
    Start-Process -FilePath "TortoiseProc.exe" -ArgumentList "/command:commit /path:`"$Path`" /notempfile" -Wait
}


function Invoke-P4ReconcileAndCommit {
    <#
    .SYNOPSIS
    使用 p4 reconcile 检测并准备目录变更，通过 p4vc 提交（仅调用一次 reconcile）
    
    .DESCRIPTION
    单次执行 p4 reconcile 完成变更检测和待提交列表更新，若存在变更则调用 p4vc 弹出提交窗口
    
    .PARAMETER Path
    需要处理的目录路径，默认为当前目录
    
    .EXAMPLE
    Invoke-P4ReconcileAndCommit
    处理当前目录的变更并提交
    
    .EXAMPLE
    Invoke-P4ReconcileAndCommit -Path "D:\projects\myapp"
    处理 D:\projects\myapp 目录的变更并提交
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path
    )

    # 检查路径是否存在
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "目录不存在或不是有效的文件夹: $Path"
        return
    }

    # 检查 Perforce 命令是否可用
    $p4Path = Get-Command -Name "p4" -ErrorAction SilentlyContinue
    $p4vcPath = Get-Command -Name "p4vc" -ErrorAction SilentlyContinue
    if (-not $p4Path -or -not $p4vcPath) {
        Write-Error "未找到 p4 或 p4vc 命令，请确保 Perforce 客户端已正确安装并添加到环境变量"
        return
    }

    try {
        # 切换到目标目录（确保 p4 命令在正确的工作区生效）
        Push-Location -Path $Path -ErrorAction Stop

        # 执行 p4 reconcile 并捕获输出（一次执行：检测并更新待提交列表）
        Write-Host "正在检测并准备目录变更: $Path"
        $reconcileOutput = p4 reconcile 2>&1

        # 检查是否有错误（如未连接到服务器、工作区未配置等）
        if ($LASTEXITCODE -ne 0) {
            Write-Error "p4 reconcile 执行失败: $reconcileOutput"
            return
        }

        # 解析输出，判断是否有需要提交的文件
        $reconcileText = [string]::Join([Environment]::NewLine, @($reconcileOutput))
        $hasChanges = $reconcileText -match "- opened for (add|edit|delete|integrate)"
        if (-not $hasChanges) {
            Write-Host "没有需要提交的变更"
            return
        }

        # 若有变更，调用 p4vc 弹出提交窗口
        Write-Host "发现变更，正在打开提交窗口..."
        Start-Process -FilePath "p4vc" -ArgumentList "pendingchanges" -Wait
    }
    catch {
        Write-Error "操作失败: $_"
    }
    finally {
        # 恢复原始工作目录
        Pop-Location
    }
}

# 添加别名，方便使用
Set-Alias -Name pvc -Value Invoke-P4ReconcileAndCommit


function extract_here {
    <#
    .SYNOPSIS
    使用 7z 解压文件到与压缩文件同名（不含后缀）的文件夹中
    
    .DESCRIPTION
    自动创建与压缩文件同名（去除后缀）的文件夹，并将内容解压到该文件夹，支持处理多后缀文件（如 .tar.gz）
    
    .PARAMETER ZipFilePath
    压缩文件的路径（绝对路径或相对路径）
    
    .EXAMPLE
    Expand-7zToNamedFolder -ZipFilePath "D:\downloads\example.tar.gz"
    # 解压 D:\downloads\example.tar.gz 到 D:\downloads\example 文件夹（保留目录结构）
    
    .EXAMPLE
    Expand-7zToNamedFolder -ZipFilePath "data.zip"
    # 解压当前目录的 data.zip 到 data 文件夹
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage="压缩文件的路径（绝对或相对路径）")]
        [string]$ZipFilePath
    )

    # 检查文件是否存在
    if (-not (Test-Path -Path $ZipFilePath -PathType Leaf)) {
        Write-Error "文件不存在：$ZipFilePath"
        return
    }

    # 获取压缩文件的完整路径和文件名
    $fullPath = Resolve-Path -Path $ZipFilePath
    $fileName = [System.IO.Path]::GetFileName($fullPath)  # 带后缀的文件名（如 example.tar.gz）
    $fileDirectory = [System.IO.Path]::GetDirectoryName($fullPath)  # 文件所在目录

    # 提取文件名（去除所有后缀，如 example.tar.gz → example）
    $folderName = $fileName
    while ($folderName -ne [System.IO.Path]::GetFileNameWithoutExtension($folderName)) {
        $folderName = [System.IO.Path]::GetFileNameWithoutExtension($folderName)
    }

    # 目标文件夹路径（文件所在目录 + 同名文件夹）
    $targetDir = Join-Path -Path $fileDirectory -ChildPath $folderName

    # 创建目标文件夹（若不存在）
    if (-not (Test-Path -Path $targetDir -PathType Container)) {
        try {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            Write-Host "已创建文件夹：$targetDir"
        }
        catch {
            Write-Error "创建文件夹失败：$_"
            return
        }
    }


    # 调用 7z 解压
    try {

        Write-Host "开始解压 $fileName 到 $targetDir ..."
        $zp = "-o$targetDir"
        & "7z" x $ZipFilePath $zp | Out-Null
        
        # 检查解压是否成功（7z 成功返回 0，其他为错误）
        if ($LASTEXITCODE -eq 0) {
            Write-Host "解压完成！" -ForegroundColor Green
        }
        else {
            Write-Error "解压失败，7z 返回代码：$LASTEXITCODE"
        }
    }
    catch {
        Write-Error "调用 7z 失败：$_"
    }
}

function rt {
    # 调用 AHK 脚本并传递当前目录
    & "C:\Users\Admin\AppData\Local\Microsoft\WindowsApps\AutoHotkey.exe" "C:\Users\Admin\Documents\AutoHotkey\run_right_menu.ahk" "$($PWD.Path)"
}
