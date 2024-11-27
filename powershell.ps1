#第一次需要执行下面几行进行安装
#Install-Module -Name PSFzf 
#Install-Module -Name PSEverything

set-psreadlinekeyhandler -key tab -function complete
$env:shell = "wt.exe"

import-module psreadline
import-module psfzf
import-module pseverything

set-psreadlineoption -predictionsource history
set-psreadlineoption -predictionviewstyle listview

invoke-expression (& {
    $hook = if ($psversiontable.psversion.major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell | out-string)
})

function op([string]$filename)
{
    search-everything $filename | invoke-fzf | % {neovide $_}
}


function opg([string]$filename)
{
    search-everything -global $filename | invoke-fzf | % {neovide $_}
}

function ccd([string]$filename)
{
    search-everything -filter $filename | invoke-fzf | % {if ((get-item $_) -is [system.io.directoryinfo]) {cd $_} else {cd (split-path -path $_)}}
}


function ccdg([string]$filename)
{
    search-everything -global -filter $filename | invoke-fzf | % {if ((get-item $_) -is [system.io.directoryinfo]) {cd $_} else {cd (split-path -path $_)}}
}


function tc([string]$filename)
{
    if (($filename) -eq ".") {
	    	c:\totalcmd\totalcmd64.exe /o /t /r=$pwd
	}
	else{
    		search-everything $filename | invoke-fzf | % {c:\totalcmd\totalcmd64.exe /o /t /r=$_}
	}
}

function tcg([string]$filename)
{
    search-everything -global $filename | invoke-fzf | % {c:\totalcmd\totalcmd64.exe /o /t /r=$_}
}
