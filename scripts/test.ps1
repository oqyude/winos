#Requires -Version 5.1
Import-Module Pester -MinimumVersion 5.0 -Force
Invoke-Pester -Path "$PSScriptRoot/../tests" -Output Detailed
