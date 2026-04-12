$bytes = [System.IO.File]::ReadAllBytes("scripts/ffmpeg-build")
$crCount = ($bytes | Where-Object { $_ -eq 13 }).Count
if ($crCount -eq 0) {
    Write-Host "OK: ffmpeg-build is LF only"
} else {
    Write-Host "FAIL: ffmpeg-build contains $crCount CR characters"
}
