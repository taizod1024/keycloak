param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = "Stop"

$cfg = Get-Content winget.config.json -Raw | ConvertFrom-Json
$assetName = "$($cfg.packageName)-$Version-Windows-x64.zip"
$releaseUrl = "https://api.github.com/repos/$($cfg.packageRepository)/releases/tags/$Version"
$release = Invoke-RestMethod -Uri $releaseUrl -Headers @{
  Authorization = "Bearer $env:GITHUB_TOKEN"
  "User-Agent" = "keycloak-winget-publish"
}
$asset = @($release.assets | Where-Object { $_.name -eq $assetName })
if ($asset.Count -ne 1) {
  throw "Expected exactly one upstream asset named '$assetName' for Keycloak $Version; found $($asset.Count)."
}

$url = $asset[0].browser_download_url
$archivePath = Join-Path $env:RUNNER_TEMP "$($cfg.packageId)-$Version.zip"
Invoke-WebRequest -Uri $url -OutFile $archivePath
$installerSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  $launcherPattern = "(?i)(^|/)$([regex]::Escape($cfg.launcher))$"
  $entries = @($archive.Entries | Where-Object { $_.FullName -match $launcherPattern })
  if ($entries.Count -ne 1) {
    throw "Expected exactly one '$($cfg.launcher)' entry in the package archive; found $($entries.Count)."
  }
  $nestedInstallerPath = $entries[0].FullName.Replace('\', '/')
}
finally {
  $archive.Dispose()
}

$token = ($env:WINGET_TOKEN -replace "`r|`n", "").Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
  throw "No GitHub token is available for winget submission."
}
if ($token -notmatch '^[A-Za-z0-9_]+$') {
  throw "GitHub token contains invalid characters."
}

$versionDir = Join-Path $pwd "winget-manifests" "manifests" "t" $cfg.publisher $cfg.packageName $Version
New-Item -ItemType Directory -Path $versionDir -Force | Out-Null

$installerPath = Join-Path $versionDir "$($cfg.packageId).installer.yaml"
$dependencyLines = @()
if ($cfg.dependencies -and $cfg.dependencies.Count -gt 0) {
  $dependencyLines += "Dependencies:"
  $dependencyLines += "  PackageDependencies:"
  foreach ($dependency in $cfg.dependencies) {
    $dependencyLines += "  - PackageIdentifier: $dependency"
  }
}
$installerLines = @(
  "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json"
  "PackageIdentifier: $($cfg.packageId)"
  "PackageVersion: $Version"
) + $dependencyLines + @(
  "Installers:"
  "- Architecture: x64"
  "  InstallerUrl: $url"
  "  InstallerSha256: $installerSha256"
  "  InstallerType: zip"
  "  NestedInstallerType: portable"
  "  NestedInstallerFiles:"
  "    - RelativeFilePath: $nestedInstallerPath"
  "      PortableCommandAlias: kc"
  "ManifestType: installer"
  "ManifestVersion: 1.12.0"
) 
$installerLines -join "`n" | Out-File -FilePath $installerPath -Encoding utf8

$defaultPath = Join-Path $versionDir "$($cfg.packageId).yaml"
@(
  "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json"
  "PackageIdentifier: $($cfg.packageId)"
  "PackageVersion: $Version"
  "DefaultLocale: en-US"
  "ManifestType: version"
  "ManifestVersion: 1.12.0"
) -join "`n" | Out-File -FilePath $defaultPath -Encoding utf8

$localePath = Join-Path $versionDir "$($cfg.packageId).locale.en-US.yaml"
@(
  "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json"
  "PackageIdentifier: $($cfg.packageId)"
  "PackageVersion: $Version"
  "PackageLocale: en-US"
  "Publisher: $($cfg.publisher)"
  "PublisherUrl: https://github.com/$($cfg.publisher)"
  "PublisherSupportUrl: https://github.com/$($cfg.packageRepository)/issues"
  "PackageName: $($cfg.packageName)"
  "PackageUrl: https://github.com/$($cfg.packageRepository)"
  "License: $($cfg.license)"
  "LicenseUrl: $($cfg.licenseUrl)"
  "ShortDescription: $($cfg.shortDescription)"
  "ManifestType: defaultLocale"
  "ManifestVersion: 1.12.0"
) -join "`n" | Out-File -FilePath $localePath -Encoding utf8

if ((Get-ChildItem -Path $versionDir -File -Filter "*.yaml").Count -ne 3) {
  throw "Expected exactly three manifest YAML files in '$versionDir'."
}

Write-Output "Submitting $($cfg.packageId) $Version using upstream installer URL: $url"
& .\wingetcreate.exe submit "$versionDir" --token $token
if ($LASTEXITCODE -ne 0) {
  throw "wingetcreate failed to submit the package manifest."
}
