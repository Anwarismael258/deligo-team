[CmdletBinding()]
param(
  [ValidateSet('all','deligo','taomoz','comunhao','sarca')]
  [string]$App = 'all'
)

$deliveryRoot = 'C:\Users\Administrator\Documents\DeliGo Triunfal Apps'
$androidRoot = Join-Path $deliveryRoot 'Android'
$webRoot = Join-Path $deliveryRoot 'Web'
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmm'

$apps = @(
  @{ Id='deligo'; Name='DeliGo - Cliente, Restaurante e Estafeta'; Root='C:\Users\Administrator\deligo_app'; Patterns=@('build\app\outputs\flutter-apk\*.apk') },
  @{ Id='taomoz'; Name='DeliGo Market - TaoMoz'; Root='C:\Users\Administrator\Documents\TaoMoz'; Patterns=@('build\app\outputs\flutter-apk\*.apk') },
  @{ Id='comunhao'; Name='Comunhao'; Root='C:\Users\Administrator\igreja'; Patterns=@('apps\comunhao\build\app\outputs\flutter-apk\*.apk','apps\comunhao_igreja\build\app\outputs\flutter-apk\*.apk') },
  @{ Id='sarca'; Name='SARCA'; Root='C:\Users\Administrator\sarca'; Patterns=@('apps\rider-mobile\build\app\outputs\flutter-apk\*.apk','apps\driver-mobile\build\app\outputs\flutter-apk\*.apk') }
)

New-Item -ItemType Directory -Force -Path $androidRoot | Out-Null
New-Item -ItemType Directory -Force -Path $webRoot | Out-Null
$published = @()

foreach ($application in $apps | Where-Object { $App -eq 'all' -or $_.Id -eq $App }) {
  $artifacts = foreach ($pattern in $application.Patterns) {
    Get-ChildItem -Path (Join-Path $application.Root $pattern) -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq '.apk' }
  }

  foreach ($artifact in $artifacts | Sort-Object LastWriteTime) {
    $appDirectory = Join-Path $androidRoot ($application.Name -replace '[\\/:*?"<>|]', '-')
    New-Item -ItemType Directory -Force -Path $appDirectory | Out-Null
    $variant = if ($artifact.BaseName -match 'release') { 'Release' } else { 'Debug' }
    $destinationName = "$($application.Name) - $variant - $timestamp.apk"
    $destination = Join-Path $appDirectory $destinationName
    Copy-Item -LiteralPath $artifact.FullName -Destination $destination
    $published += [pscustomobject]@{
      application = $application.Name
      variant = $variant
      file = $destination
      source = $artifact.FullName
      built_at = $artifact.LastWriteTime.ToString('o')
      size_mb = [math]::Round($artifact.Length / 1MB, 2)
    }
  }
}

if ($App -in @('all','taomoz')) {
  $taomozDist = 'C:\Users\Administrator\Documents\TaoMoz\dist'
  if (Test-Path -LiteralPath $taomozDist) {
    $marketDirectory = Join-Path $webRoot 'DeliGo Market - TaoMoz'
    New-Item -ItemType Directory -Force -Path $marketDirectory | Out-Null
    $marketArchive = Join-Path $marketDirectory "DeliGo Market - TaoMoz - Web - $timestamp.zip"
    Compress-Archive -Path (Join-Path $taomozDist '*') -DestinationPath $marketArchive
    $published += [pscustomobject]@{
      application = 'DeliGo Market - TaoMoz'
      variant = 'Web PWA'
      file = $marketArchive
      source = $taomozDist
      built_at = (Get-Item -LiteralPath $taomozDist).LastWriteTime.ToString('o')
      size_mb = [math]::Round((Get-Item -LiteralPath $marketArchive).Length / 1MB, 2)
    }
  }
}

$catalogPath = Join-Path $deliveryRoot 'catalogo.json'
$existing = if (Test-Path -LiteralPath $catalogPath) { @(Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json) } else { @() }
$allRecords = [System.Collections.Generic.List[object]]::new()
foreach ($record in @($existing)) { $allRecords.Add($record) }
foreach ($record in @($published)) { $allRecords.Add($record) }
$allRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $catalogPath -Encoding utf8

if ($published.Count) {
  $published | Format-Table application,variant,size_mb,file -AutoSize
} else {
  Write-Warning 'Nenhum APK compilado foi encontrado para as aplicações selecionadas.'
}
