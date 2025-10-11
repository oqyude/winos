param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("install","uninstall")]
    [string]$Mode
)

$packageList = @(
    "MartiCliment.UniGetUI"
)

if (-not (checkWingetStatus)) {
    Write-Host "winget is not available. Aborting." -ForegroundColor Red
    return
}

foreach ($pkg in $packageList) {
    switch ($Mode) {
        "install" {
            Write-Host "Installing $pkg..." -ForegroundColor Cyan
            try {
                winget install --id $pkg --silent --accept-package-list-agreements --accept-source-agreements
            }
            catch {
                Write-Host "Failed to install $pkg : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "uninstall" {
            Write-Host "Uninstalling $pkg..." -ForegroundColor Cyan
            try {
                winget uninstall --id $pkg --silent
            }
            catch {
                Write-Host "Failed to uninstall $pkg : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
Write-Host "All requested packages processed." -ForegroundColor Green
