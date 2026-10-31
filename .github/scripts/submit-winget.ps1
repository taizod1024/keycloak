param(
  [Parameter(Mandatory)]
  [string]$WingetCreatePath,

  [Parameter(Mandatory)]
  [string]$PackageId,

  [Parameter(Mandatory)]
  [string]$Version,

  [Parameter(Mandatory)]
  [string]$UserInstallerUrl,

  [Parameter(Mandatory)]
  [string]$MachineInstallerUrl,

  [Parameter(Mandatory)]
  [string]$Token
)

$ErrorActionPreference = "Stop"

$cfg = Get-Content (Join-Path $PSScriptRoot "..\..\winget.config.json") -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Token)) {
  throw "No GitHub token is available for winget submission."
}
if ($Token -notmatch '^[A-Za-z0-9_]+$') {
  throw "GitHub token contains invalid characters."
}
if ($PackageId -ne $cfg.packageId) {
  throw "PackageId must match winget.config.json ($($cfg.packageId))."
}
if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
  throw "Version contains invalid characters."
}
if (-not (Test-Path -LiteralPath $WingetCreatePath -PathType Leaf)) {
  throw "wingetcreate was not found at '$WingetCreatePath'."
}

$manifestRoot = Join-Path $env:RUNNER_TEMP "winget-manifest"
if (Test-Path -LiteralPath $manifestRoot) {
  Remove-Item -LiteralPath $manifestRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $manifestRoot | Out-Null

function Get-MsiProperty([string]$Path, [string]$Name) {
  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @((Resolve-Path -LiteralPath $Path).Path, 0))
  $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, @("SELECT Value FROM Property WHERE Property='$Name'"))
  $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null
  $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
  $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
  $view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null) | Out-Null
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
  return $value
}

$installers = @()
foreach ($item in @(@{ Scope = "user"; Url = $UserInstallerUrl }, @{ Scope = "machine"; Url = $MachineInstallerUrl })) {
  $msiPath = Join-Path $manifestRoot "$($cfg.packageName)-$Version-x64-$($item.Scope).msi"
  Invoke-WebRequest -Uri $item.Url -OutFile $msiPath
  $installers += @{
    Scope       = $item.Scope
    Url         = $item.Url
    Sha256      = (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToUpperInvariant()
    ProductCode = Get-MsiProperty $msiPath "ProductCode"
  }
}

$separatorIndex = $PackageId.IndexOf(".")
if ($separatorIndex -lt 1 -or $separatorIndex -eq $PackageId.Length - 1) {
  throw "PackageId must contain a publisher and package name separated by a period."
}

$publisher = $PackageId.Substring(0, $separatorIndex)
$packageIdentifierName = $PackageId.Substring($separatorIndex + 1)
$publisherInitial = $publisher.Substring(0, 1).ToLowerInvariant()
$versionDirectory = Join-Path $manifestRoot "manifests"
$versionDirectory = Join-Path $versionDirectory $publisherInitial
$versionDirectory = Join-Path $versionDirectory $publisher
$versionDirectory = Join-Path $versionDirectory $packageIdentifierName
$versionDirectory = Join-Path $versionDirectory $Version
New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null

$dependencyLines = @()
if ($cfg.dependencies -and $cfg.dependencies.Count -gt 0) {
  $dependencyLines += "Dependencies:"
  $dependencyLines += "  PackageDependencies:"
  foreach ($dependency in $cfg.dependencies) {
    $dependencyLines += "  - PackageIdentifier: $dependency"
  }
}

$installerEntries = foreach ($installer in $installers) {
@"
- Architecture: x64
  Scope: $($installer.Scope)
  InstallerUrl: $($installer.Url)
  InstallerSha256: $($installer.Sha256)
  InstallerType: wix
  ProductCode: '$($installer.ProductCode)'
  UpgradeBehavior: install
"@
}

$installerManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.1.12.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
$($dependencyLines -join "`n")
Installers:
$($installerEntries -join "`n")
ManifestType: installer
ManifestVersion: 1.12.0
"@

$versionManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.1.12.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.12.0
"@

$localeManifest = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.1.12.0.schema.json
PackageIdentifier: $PackageId
PackageVersion: $Version
PackageLocale: en-US
Publisher: $($cfg.publisher)
PublisherUrl: https://github.com/$($cfg.publisher)
PublisherSupportUrl: https://github.com/$($cfg.packageRepository)/issues
PackageName: $($cfg.packageName)
PackageUrl: https://github.com/$($cfg.packageRepository)
License: $($cfg.license)
LicenseUrl: $($cfg.licenseUrl)
ShortDescription: $($cfg.shortDescription)
Description: $($cfg.description)
Moniker: $($cfg.moniker)
Tags:
$(($cfg.tags | ForEach-Object { "- $_" }) -join "`n")
ManifestType: defaultLocale
ManifestVersion: 1.12.0
"@

$manifestFiles = @{
  "$PackageId.installer.yaml" = $installerManifest
  "$PackageId.yaml" = $versionManifest
  "$PackageId.locale.en-US.yaml" = $localeManifest
}
$encoding = [System.Text.UTF8Encoding]::new($false)
foreach ($fileName in $manifestFiles.Keys) {
  $filePath = Join-Path $versionDirectory $fileName
  [System.IO.File]::WriteAllText($filePath, $manifestFiles[$fileName], $encoding)
}

if ($installerManifest -notmatch "(?m)^  Scope: user\r?$" -or $installerManifest -notmatch "(?m)^  Scope: machine\r?$") {
  throw "The installer manifest must include both user and machine scopes."
}

$manifestApiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$publisherInitial/$publisher/$packageIdentifierName/$Version"
$versionAlreadyExists = $false
try {
  Invoke-RestMethod -Headers @{
    Authorization = "Bearer $Token"
    "User-Agent" = "keycloak-winget-publish"
  } -Uri $manifestApiUrl | Out-Null
  $versionAlreadyExists = $true
}
catch {
  $statusCode = 0
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
    $statusCode = [int]$_.Exception.Response.StatusCode
  }
  if ($statusCode -ne 404) {
    throw "Unable to check whether winget version '$Version' already exists: $($_.Exception.Message)"
  }
}

$submitArguments = @("submit", "--token", $Token, "--no-open")
if ($versionAlreadyExists) {
  $submitArguments += @("--replace", $Version)
}
$submitArguments += $versionDirectory

& $WingetCreatePath @submitArguments
if ($LASTEXITCODE -ne 0) {
  throw "wingetcreate submit failed with exit code $LASTEXITCODE."
}
