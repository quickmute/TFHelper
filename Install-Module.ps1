$userModulesDir = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
$moduleName = $(Get-Item -Path $PSScriptRoot).BaseName
$moduleInstallFolder = Join-Path -Path $userModulesDir -ChildPath $moduleName
if ((Test-Path -Path $moduleInstallFolder) -eq $true) {
    Write-Host "Removing old installation..."
    Remove-Item -Path $moduleInstallFolder -Recurse
}
Write-Host $moduleFolder
Copy-Item -Path $PSScriptRoot -Destination $userModulesDir -Recurse -Exclude "Install-Module.ps1"
