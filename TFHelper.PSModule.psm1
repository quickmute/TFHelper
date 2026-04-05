Get-ChildItem -Path $PSScriptRoot\Functions -Filter '*.ps1' | ForEach-Object {
    Try {
        . $_.FullName
    }
    Catch {
        Write-Host "Failed to import function: $($_.Exception.Message)"
    }
}
