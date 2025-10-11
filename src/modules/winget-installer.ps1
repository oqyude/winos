param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("check","install")]
    [string]$Mode
)
function install {
    if (checkWingetStatus) {
        Write-Host "Skipping installation, winget already present." -ForegroundColor Cyan
        return
    }
    $wingetUrl  = "https://aka.ms/getwinget"
    $wingetFile = "$tempFolder\winget.msixbundle"
    try {
        Write-Host "Downloading winget..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetFile -UseBasicParsing

        Write-Host "Installing winget..." -ForegroundColor Cyan
        Add-AppxPackage $wingetFile

        Write-Host "winget successfully installed." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install winget: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if (Test-Path $wingetFile) { Remove-Item $wingetFile -Force }
    }
}

switch ($Mode) {
    "check"   { return checkWingetStatus | Out-Null }
    "install" { install }
}
