param([string]$Godot = "$PSScriptRoot\tools\Godot_v4.6-stable_win64_console.exe", [switch]$Render)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force 'tests\artifacts' | Out-Null
    $battleLog = Join-Path $PSScriptRoot 'tests\artifacts\battle.log'
    & $Godot --headless --path . --log-file $battleLog --script tests/test_battle.gd
    if ($LASTEXITCODE -ne 0) { throw 'Battle tests failed.' }
    if (Select-String -LiteralPath $battleLog -Pattern 'SCRIPT ERROR|FAIL:' -Quiet) { throw 'Battle script error.' }
    $uiLog = Join-Path $PSScriptRoot 'tests\artifacts\ui.log'
    $uiArgs = @('--path', '.', '--log-file', $uiLog, '--script', 'tests/smoke_ui.gd')
    if (-not $Render) { $uiArgs = @('--headless') + $uiArgs }
    $uiArgs += @('--', '--save-log')
    & $Godot @uiArgs
    if ($LASTEXITCODE -ne 0) { throw 'UI tests failed.' }
    if (Select-String -LiteralPath $uiLog -Pattern 'SCRIPT ERROR|FAIL UI:' -Quiet) { throw 'UI script error.' }
    Write-Output 'All battle and UI checks passed.'
} finally {
    Pop-Location
}
