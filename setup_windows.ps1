$ErrorActionPreference = 'Stop'
Write-Host "Video Downloader project setup" -ForegroundColor Cyan
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter was not found in PATH. Install Flutter or add flutter\bin to PATH."
}
flutter pub get
Write-Host "Setup completed. Run: flutter run" -ForegroundColor Green
