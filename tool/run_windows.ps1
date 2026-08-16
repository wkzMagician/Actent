param(
  [string]$Device = 'windows',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

flutter run -d $Device @FlutterArgs
