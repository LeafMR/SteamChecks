$GithubChecksumUrl = "https://raw.githubusercontent.com/LeafMR/Checks/refs/heads/main/Checks.zip.sha256"
$GithubAssetUrl    = "https://github.com/LeafMR/Checks/releases/download/v1.0.0/Checks.zip"
$ExpectedExecutableRelativePath = "checker.exe"
$AppFolder = Join-Path -Path $env:LOCALAPPDATA -ChildPath "CheckerBootstrap"
$LogFile = Join-Path $AppFolder "bootstrap.log"

if (-not (Test-Path $AppFolder)) { New-Item -ItemType Directory -Path $AppFolder | Out-Null }

function Log {
  param($s)
  $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  "$t`t$s" | Out-File -FilePath $LogFile -Append -Encoding utf8
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
if (-not $remoteChecksumText) { Write-Host "Could not fetch checksum."; exit 1 }
$expectedSha = ParseChecksum -text $remoteChecksumText
if (-not $expectedSha)      { Write-Host "Invalid checksum format."; exit 1 }
Log "Expected SHA256: $expectedSha"

$haveValidLocal = $false
if (Test-Path $localZipPath) {
  Log "Found local zip at $localZipPath — hashing."
  $localSha = ComputeSHA256 -file $localZipPath
  if ($localSha) {
    Log "Local SHA256: $localSha"
    if ($localSha -eq $expectedSha) { $haveValidLocal = $true; Log "Local zip matches expected." }
    else { Log "Checksum mismatch; will re-download." }
  }
} else {
  Log "No local zip found."
}

if (-not $haveValidLocal) {
  Write-Host "Downloading official checker..."
  if (-not (DownloadFile -url $GithubAssetUrl -outPath $localZipPath)) {
    Write-Host "Download failed. See log at $LogFile"; exit 1
  }
  $downloadedSha = ComputeSHA256 -file $localZipPath
  if (-not $downloadedSha) { Write-Host "Hashing failed."; exit 1 }
  Log "Downloaded SHA256: $downloadedSha"
  if ($downloadedSha -ne $expectedSha) {
    Write-Host "Checksum mismatch on downloaded file. Aborting."
    Log "Checksum mismatch after download — abort."
    exit 1
  }
  Log "Downloaded file verified."
}

if (Test-Path $extractedFolder) { try { Remove-Item -Path $extractedFolder -Recurse -Force -ErrorAction Stop } catch {} }
New-Item -ItemType Directory -Path $extractedFolder | Out-Null
if (-not (ExtractZip -zipPath $localZipPath -destFolder $extractedFolder)) {
  Write-Host "Extract failed. See log."; exit 1
}

if (-not (Test-Path $localExePath)) {
  Write-Host "Executable not found after extract: $ExpectedExecutableRelativePath"
  Log "Missing exe: $localExePath"
  exit 1
}

Write-Host "About to run: $localExePath"
$ans = Read-Host "Type YES to run (or anything else to cancel)"
if ($ans -ne 'YES') { Write-Host "Canceled."; Log "User canceled."; exit 0 }

Log "Launching $localExePath"
Start-Process -FilePath $localExePath
Log "Bootstrap finished."

exit 0
