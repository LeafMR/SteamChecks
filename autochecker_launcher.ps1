<<<<<<< HEAD

# autochecker_launcher.ps1
param(
  [string]$BundleUrl = "https://example.com/path/to/Checks.zip",
  [string]$ExpectedSha256 = "",
=======
param(
  [string]$BundleUrl = "https://github.com/user-attachments/files/22986550/Checks.zip",
  [string]$ExpectedSha256 = "b49bfbe58dd827836d69cfb5188b014a8cfcc29c25ce8c010e6f4361033b5640",
>>>>>>> 7619ae1 (Add autochecker launchers and README)
  [switch]$Ephemeral,
  [switch]$ForceReinstall
)
$ErrorActionPreference = "Stop"
$app = "autochecker"
$cacheRoot = Join-Path $env:LOCALAPPDATA "$app\cache"
New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null

function Get-Sha256([string]$Path) {
  (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

$tmp = New-TemporaryFile
try {
  Invoke-WebRequest -Uri $BundleUrl -OutFile $tmp -UseBasicParsing | Out-Null
  $etag = ($_.Headers.ETag) -replace '"',''
} catch {
  Write-Error "Failed to download bundle: $_"
  exit 1
}

$digest = Get-Sha256 $tmp
if ($ExpectedSha256 -and ($digest.ToLower() -ne $ExpectedSha256.ToLower())) {
  Write-Error "SHA256 mismatch. Got $digest expected $ExpectedSha256"
  exit 2
}

$version = if ($etag) { $etag } else { $digest.Substring(0,12) }
$installDir = Join-Path $cacheRoot $version

if ((Test-Path $installDir) -and (-not $ForceReinstall)) {
<<<<<<< HEAD
  # reuse cache
=======
>>>>>>> 7619ae1 (Add autochecker launchers and README)
} else {
  if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($tmp, $installDir)
}

<<<<<<< HEAD
$candidates = @("run.ps1","run.bat","run.cmd","main.exe")
$subdirs = @("","dist","build","out")
=======
$candidates = @("Main_Checker.bat","checker.ps1","run.ps1","run.bat","run.cmd","main.exe")
$subdirs = @("","Checks","dist","build","out")
>>>>>>> 7619ae1 (Add autochecker launchers and README)
$entry = $null
foreach ($sub in $subdirs) {
  $base = if ($sub) { Join-Path $installDir $sub } else { $installDir }
  foreach ($c in $candidates) {
    $p = Join-Path $base $c
    if (Test-Path $p) { $entry = $p; break }
  }
  if ($entry) { break }
}

if (-not $entry) {
  Write-Error "[autochecker] No Windows entrypoint found. Update candidates."
  exit 3
}

if ($entry.ToLower().EndsWith(".ps1")) {
  & powershell -ExecutionPolicy Bypass -File $entry @args
  $rc = $LASTEXITCODE
} elseif ($entry.ToLower().EndsWith(".bat") -or $entry.ToLower().EndsWith(".cmd")) {
  & $entry @args
  $rc = $LASTEXITCODE
} else {
  & $entry @args
  $rc = $LASTEXITCODE
}

if ($Ephemeral) { Remove-Item -Recurse -Force $installDir }
exit $rc
