$GithubChecksumUrl = "https://raw.githubusercontent.com/LeafMR/Checks/refs/heads/main/SteamChecks.zip.sha256"
$GithubAssetUrl = "https://raw.githubusercontent.com/LeafMR/Checks/refs/heads/main/Checks.zip"
$ExpectedExecutableRelativePath = "checker.ps1"

$AppFolder = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Steam_CheckerBootstrap"
$LogFile = Join-Path $AppFolder "bootstrap.log"
$LocalChecksumFile = Join-Path $AppFolder "SteamChecks.zip.sha256"

if (-not (Test-Path $AppFolder)) { New-Item -ItemType Directory -Path $AppFolder | Out-Null }

function Log {
  param([string]$s)
  $s | Out-File -FilePath $LogFile -Append -Encoding utf8
  Write-Host $s
}

function GetRemoteText {
  param($url)
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent","Steam_CheckerBootstrap/1.0")
    return $wc.DownloadString($url)
  } catch {
    Log "ERROR: couldn't fetch remote checksum."
    Log "DETAILS: $($_.Exception.Message)"
    return $null
  }
}

function ComputeSHA256 {
  param($file)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($file)
    $hb = $sha.ComputeHash($fs)
    $fs.Close()
    ($hb | ForEach-Object { $_.ToString("x2") }) -join ""
  } catch {
    Log "ERROR: failed to hash file: $file"
    Log "DETAILS: $($_.Exception.Message)"
    return $null
  }
}

function DownloadFile {
  param($url, $outPath)
  try {
    Log "Downloading check files..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent","Steam_CheckerBootstrap/1.0")
    $wc.DownloadFile($url, $outPath)
    return $true
  } catch {
    Log "ERROR: download failed."
    Log "DETAILS: $($_.Exception.Message)"
    return $false
  }
}

function ExtractZip {
  param($zipPath, $destFolder)
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $destFolder) { Remove-Item $destFolder -Recurse -Force }
    Log "Extracting .ZIP file..."
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destFolder)
    return $true
  } catch {
    Log "ERROR: extract failed."
    Log "DETAILS: $($_.Exception.Message)"
    return $false
  }
}

function ParseChecksum {
  param($text)
  if (-not $text) { return $null }
  $line = $text.Trim().Split("`n")[0].Trim()
  if ($line -match "([0-9a-fA-F]{64})") { return $matches[1].ToLower() }
  $null
}

Log "Bootstrap started."

$localZipPath = Join-Path $AppFolder "Checks.zip"
$extractedFolder = Join-Path $AppFolder "extracted"
$localExePath = Join-Path $extractedFolder $ExpectedExecutableRelativePath

$remoteChecksumText = GetRemoteText -url $GithubChecksumUrl
if (-not $remoteChecksumText) { Log "Aborting."; exit 1 }
$expectedSha = ParseChecksum -text $remoteChecksumText
if (-not $expectedSha) { Log "ERROR: invalid checksum format. Aborting."; exit 1 }

function EnsureValidZip {
  param($zipPath, $expectedSha)
  $attempt = 0
  while ($attempt -lt 3) {
    $attempt++

    if (Test-Path $zipPath) {
      $localSha = ComputeSHA256 -file $zipPath
      if ($localSha -and $localSha -eq $expectedSha) {
        Log "Downloaded files & verified integrity successfully (attempt $attempt)."
        return $true
      } else {
        if ($localSha) {
          Log "Checksum mismatch (attempt $attempt). Redownloading..."
        } else {
          Log "Could not compute local checksum (attempt $attempt). Redownloading..."
        }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
      }
    }

    if (-not (DownloadFile -url $GithubAssetUrl -outPath $zipPath)) {
      Log "Download failed (attempt $attempt)."
      Start-Sleep 2
      continue
    }

    $downloadedSha = ComputeSHA256 -file $zipPath
    if ($downloadedSha -and $downloadedSha -eq $expectedSha) {
      Log "Downloaded files & verified integrity successfully (attempt $attempt)."
      return $true
    } else {
      Log "ERROR: checksum mismatch after download (attempt $attempt)."
      Log "Aborting."
      return $false
    }
  }
  return $false
}

if (-not (EnsureValidZip -zipPath $localZipPath -expectedSha $expectedSha)) {
  Log "Failed to get valid files. Aborting."
  exit 1
}

if (-not (ExtractZip -zipPath $localZipPath -destFolder $extractedFolder)) {
  Log "Extract failed. Aborting."
  exit 1
}

Get-ChildItem -Path $extractedFolder -Recurse -File | ForEach-Object {
  try { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
}

if (-not (Test-Path $localExePath)) {
  Log "ERROR: couldn't find Checks entry script: $ExpectedExecutableRelativePath"
  exit 1
}

Log "Launching Checks..."
Push-Location $extractedFolder
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $localExePath
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($code -ne 0) {
  Log "[checker.ps1] exited with code $code"
  exit $code
}

Log "Bootstrap finished successfully."
exit 0


