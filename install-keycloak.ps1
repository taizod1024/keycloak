param(
  [Parameter(Mandatory)][string]$Url,
  [Parameter(Mandatory)][string]$Sha256,
  [Parameter(Mandatory)][string]$Target
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Target = $Target.TrimEnd('\')
$work = Join-Path ([IO.Path]::GetTempPath()) ("keycloak-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null

try {
  $zip = Join-Path $work "keycloak.zip"
  Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing

  $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  if ($actual -ne $Sha256) {
    throw "SHA256 mismatch for $Url. Expected $Sha256 but got $actual."
  }

  $extract = Join-Path $work "extract"
  Expand-Archive -LiteralPath $zip -DestinationPath $extract
  $roots = @(Get-ChildItem -LiteralPath $extract -Directory)
  if ($roots.Count -ne 1 -or -not (Test-Path (Join-Path $roots[0].FullName "bin\kc.bat"))) {
    throw "Unexpected Keycloak archive layout."
  }
  $source = $roots[0].FullName

  # Directories holding user data or customizations survive upgrades; only missing files are added.
  $keep = @("conf", "data", "providers", "themes")
  $self = Split-Path -Leaf $PSCommandPath

  New-Item -ItemType Directory -Path $Target -Force | Out-Null
  Get-ChildItem -LiteralPath $Target -Force |
    Where-Object { $_.Name -ne $self -and $_.Name -notin $keep } |
    Remove-Item -Recurse -Force

  foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
    $dest = Join-Path $Target $item.Name
    if ($item.PSIsContainer -and $item.Name -in $keep) {
      foreach ($file in Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force) {
        $relative = $file.FullName.Substring($item.FullName.Length).TrimStart('\')
        $fileDest = Join-Path $dest $relative
        if (-not (Test-Path -LiteralPath $fileDest)) {
          New-Item -ItemType Directory -Path (Split-Path -Parent $fileDest) -Force | Out-Null
          Copy-Item -LiteralPath $file.FullName -Destination $fileDest
        }
      }
      New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    else {
      Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
    }
  }
}
finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
