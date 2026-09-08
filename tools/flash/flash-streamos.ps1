#Requires -Version 5.1
<#
.SYNOPSIS
  Safe CLI flasher for Loki StreamOS raw .img artifacts (Windows).
.NOTES
  Requires Administrator. Does NOT run on the Loki device.
  Does not download or execute external binaries at runtime.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Image,

    [Parameter(Position = 1)]
    [int]$Disk,

    [string]$Checksum,

    [switch]$DryRun,
    [switch]$Verify,
    [switch]$ForceNonRemovable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 1 }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProtectedDisks {
    $protected = @()
    Get-Partition | Where-Object { $_.DriveLetter -eq 'C' -or $_.IsSystem -or $_.IsBoot } | ForEach-Object {
        $protected += $_.DiskNumber
    }
    $protected | Select-Object -Unique
}

function Show-Candidates {
    $protected = Get-ProtectedDisks
    Get-Disk | ForEach-Object {
        $d = $_
        if ($protected -contains $d.Number) { return }
        if (-not $ForceNonRemovable -and $d.BusType -notin @('USB', 'SD')) { return }
        $parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
            Select-Object PartitionNumber, DriveLetter, Size, Type
        [PSCustomObject]@{
            DiskNumber   = $d.Number
            FriendlyName = $d.FriendlyName
            BusType      = $d.BusType
            SizeGB       = [math]::Round($d.Size / 1GB, 2)
            PartitionStyle = $d.PartitionStyle
            Partitions   = ($parts | Format-Table -AutoSize | Out-String).Trim()
        }
    } | Format-Table -AutoSize
}

function Test-Checksum {
    param([string]$Img, [string]$SumFile)
    if (-not (Test-Path $SumFile)) {
        Write-Warning "No checksum file at $SumFile — image NOT verified."
        if ($DryRun) { return 'NOT VERIFIED (dry-run)' }
        $ans = Read-Host "Continue without checksum verification? Type YES"
        if ($ans -ne 'YES') { Fail 'Aborted (no checksum verification)' }
        return 'NOT VERIFIED'
    }
    Write-Host "Verifying SHA-256 from $SumFile ..."
    if ($DryRun) { return 'VERIFIED (dry-run)' }
    $expected = (Get-Content $SumFile -TotalCount 1) -split '\s+' | Select-Object -First 1
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Img).Hash.ToLower()
    if ($expected.ToLower() -ne $actual) { Fail "SHA-256 verification FAILED" }
    return 'VERIFIED'
}

function Confirm-Target {
    param([int]$DiskNumber)
    $expected = "FLASH DISK $DiskNumber"
    Write-Host "Type exactly:`n`n  $expected`n"
    $ans = Read-Host '>'
    if ($ans -ne $expected) { Fail 'Confirmation mismatch — aborted' }
}

function Write-RawImage {
    param([string]$ImgPath, [int]$DiskNumber)
    $path = "\\.\PhysicalDrive$DiskNumber"
    Write-Host "Writing to $path ..."
    if ($DryRun) {
        Write-Host "[dry-run] would write $ImgPath -> $path (raw stream, 4MB blocks)"
        return 'PowerShell raw stream'
    }
    Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
    $src = [System.IO.File]::OpenRead($ImgPath)
    try {
        $dst = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        try {
            $buf = New-Object byte[] (4MB)
            $total = $src.Length
            $done = 0L
            while (($read = $src.Read($buf, 0, $buf.Length)) -gt 0) {
                $dst.Write($buf, 0, $read)
                $dst.Flush()
                $done += $read
                $pct = if ($total -gt 0) { [math]::Round(100 * $done / $total, 1) } else { 0 }
                Write-Progress -Activity 'Writing StreamOS image' -PercentComplete $pct
            }
            Write-Progress -Activity 'Writing StreamOS image' -Completed
        } finally { $dst.Close() }
    } finally { $src.Close() }
    return 'PowerShell raw stream'
}

# --- main ---
if (-not $DryRun -and -not (Test-Admin)) {
    Fail 'Administrator privileges required. Re-run PowerShell as Administrator.'
}

if (-not (Test-Path $Image)) { Fail "Image not found: $Image" }
if ($Image -notmatch '\.img$') { Fail 'Only raw .img images are supported on Windows (not .img.zst yet).' }

$protected = Get-ProtectedDisks
if (-not $PSBoundParameters.ContainsKey('Disk')) {
    Write-Host 'Candidate disks:'
    Show-Candidates
    $Disk = [int](Read-Host 'Enter physical disk number')
}

if ($protected -contains $Disk) { Fail "Refusing to write system/boot disk: Disk $Disk" }

$target = Get-Disk -Number $Disk -ErrorAction Stop
if (-not $ForceNonRemovable -and $target.BusType -notin @('USB', 'SD')) {
    Fail "Disk $Disk is not USB/SD. Use -ForceNonRemovable if certain."
}

Write-Host ''
Write-Host 'STREAMOS FLASH TARGET'
Write-Host ''
Write-Host "Disk:       $($target.Number)"
Write-Host "Model:      $($target.FriendlyName)"
Write-Host "Capacity:   $([math]::Round($target.Size/1GB,2)) GB"
Write-Host "Bus:        $($target.BusType)"
Write-Host ''
Write-Host "ALL DATA ON PHYSICAL DISK $Disk WILL BE DESTROYED."
Write-Host ''

$sumFile = if ($Checksum) { $Checksum } else { "$Image.sha256" }
$checksumStatus = Test-Checksum -Img $Image -SumFile $sumFile

if (-not $DryRun) { Confirm-Target -DiskNumber $Disk }

Get-Partition -DiskNumber $Disk -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter } |
    ForEach-Object {
        $letter = "$($_.DriveLetter):"
        Write-Host "Clearing volume $letter ..."
        if (-not $DryRun) {
            Remove-PartitionAccessPath -DiskNumber $Disk -PartitionNumber $_.PartitionNumber -AccessPath $letter -ErrorAction SilentlyContinue
        }
    }

$writer = Write-RawImage -ImgPath (Resolve-Path $Image) -DiskNumber $Disk

if (-not $DryRun) {
    Start-Sleep -Seconds 2
    Update-Disk -Number $Disk
    Write-Host ''
    Write-Host 'Resulting partitions:'
    Get-Partition -DiskNumber $Disk | Format-Table -AutoSize
    if ($Verify) {
        Write-Host ''
        Write-Host 'Verification (partition table only):'
        Get-Partition -DiskNumber $Disk | Format-List
    }
}

if ($DryRun) { Write-Host '[dry-run] complete — no changes made'; exit 0 }

Write-Host ''
Write-Host 'StreamOS image written successfully.'
Write-Host ''
Write-Host "Image:  $Image"
Write-Host "Target: PhysicalDisk $Disk ($($target.FriendlyName))"
Write-Host "SHA-256: $checksumStatus"
Write-Host "Writer:  $writer"
Write-Host ''
Write-Host 'Safe to remove media.'
