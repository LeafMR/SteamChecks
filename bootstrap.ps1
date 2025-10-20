$GithubChecksumUrl = "https://raw.githubusercontent.com/LeafMR/Checks/refs/heads/main/Checks.zip.sha256"
$GithubAssetUrl    = "https://github.com/LeafMR/Checks/releases/download/v1.0.0/Checks.zip"
$ExpectedExecutableRelativePath = "checker.ps1"

$AppFolder = Join-Path -Path $env:LOCALAPPDATA -ChildPath "CheckerBootstrap"
$LogFile   = Join-Path $AppFolder "bootstrap.log"

if (-not (Test-Path $AppFolder)) { New-Item -ItemType Directory -Path $AppFolder | Out-Null }

function Log {
  param($s)
  $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  "$t`t$s" | Out-File -FilePath $LogFile -Append -Encoding utf8
  Write-Host "$t`t$s"
}

function GetRemoteText {
  param($url)
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent","CheckerBootstrap/1.0")
    return $wc.DownloadString($url)
  } catch {
    Log "ERROR fetching $url : $_"
    return $null
  }
}

function ComputeSHA256 {
  param($file)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs  = [System.IO.File]::OpenRead($file)
    $hb  = $sha.ComputeHash($fs)
    $fs.Close()
    ($hb | ForEach-Object { $_.ToString("x2") }) -join ""
  } catch {
    Log "ERROR hashing $file : $_"; return $null
  }
}

function DownloadFile {
  param($url, $outPath)
  try {
    Log "Downloading $url -> $outPath"
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent","CheckerBootstrap/1.0")
    $wc.DownloadFile($url, $outPath)
    return $true
  } catch {
    Log "ERROR download failed: $_"; return $false
  }
}

function ExtractZip {
  param($zipPath, $destFolder)
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destFolder)
    return $true
  } catch {
    Log "ERROR extract failed: $_"; return $false
  }
}

function ParseChecksum {
  param($text)
  if (-not $text) { return $null }
  $line = $text.Trim().Split("`n")[0].Trim()
  if ($line -match "([0-9a-fA-F]{64})") { return $matches[1].ToLower() }
  $null
}

Log "Bootstrap start."

$localZipPath    = Join-Path $AppFolder "Checks.zip"
$extractedFolder = Join-Path $AppFolder "extracted"
$localExePath    = Join-Path $extractedFolder $ExpectedExecutableRelativePath

$remoteChecksumText = GetRemoteText -url $GithubChecksumUrl
if (-not $remoteChecksumText) { Log "Could not fetch checksum."; exit 1 }
$expectedSha = ParseChecksum -text $remoteChecksumText
if (-not $expectedSha) { Log "Invalid checksum format."; exit 1 }

Log "Expected SHA256: $expectedSha"

function EnsureValidZip {
  param($zipPath, $expectedSha)
  $attempt = 0
  while ($true) {
    $attempt++
    if (Test-Path $zipPath) {
      $localSha = ComputeSHA256 -file $zipPath
      if ($localSha -eq $expectedSha) {
        Log "Zip verified successfully (attempt $attempt)."
        return $true
      } else {
        Log "Checksum mismatch (attempt $attempt): expected $expectedSha, got $localSha. Re-downloading..."
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
      }
    }
    if (-not (DownloadFile -url $GithubAssetUrl -outPath $zipPath)) {
      Log "Download failed (attempt $attempt)."
      if ($attempt -ge 3) { Log "Failed after 3 attempts."; return $false }
      Start-Sleep 2
      continue
    }
  }
}

if (-not (EnsureValidZip -zipPath $localZipPath -expectedSha $expectedSha)) {
  Log "Could not obtain a valid ZIP after retries. Aborting."
  exit 1
}

if (Test-Path $extractedFolder) { try { Remove-Item -Path $extractedFolder -Recurse -Force -ErrorAction Stop } catch {} }
New-Item -ItemType Directory -Path $extractedFolder | Out-Null

if (-not (ExtractZip -zipPath $localZipPath -destFolder $extractedFolder)) {
  Log "Extract failed. Aborting."
  exit 1
}

Get-ChildItem -Path $extractedFolder -Recurse -File | ForEach-Object {
  try { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
}

if (-not (Test-Path $localExePath)) {
  Log "Executable not found: $ExpectedExecutableRelativePath"
  exit 1
}

Log "Launching PowerShell script: $localExePath"
Start-Process -FilePath "powershell.exe" -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", "`"$localExePath`""
) -WorkingDirectory $extractedFolder

Log "Bootstrap finished successfully."
exit 0
