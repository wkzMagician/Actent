$projectRoot = Split-Path -Parent $PSScriptRoot
$icon = Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'
flutter build linux --dart-define="RESIDENT_ICON_PATH=$icon" @args
