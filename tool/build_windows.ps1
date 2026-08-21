param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$icon = (Resolve-Path (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico')).Path
flutter build windows @FlutterArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Keep the tray icon beside the executable. The relative path remains valid
# when the release directory is copied to another machine.
$releaseDir = (Resolve-Path (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release')).Path
Copy-Item -LiteralPath $icon -Destination (Join-Path $releaseDir 'app_icon.ico') -Force

$version = (Select-String -Path (Join-Path $PSScriptRoot '..\pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches.Groups[1].Value
if (-not $version) { throw 'pubspec.yaml version not found' }
$compiler = (Get-Command ISCC.exe -ErrorAction Stop).Source
& $compiler "/DMyAppVersion=$version" (Join-Path $PSScriptRoot '..\installer\windows.iss')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
