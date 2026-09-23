@echo off
setlocal
set "GRADLE_VERSION=8.11.1"
set "GRADLE_HOME=%USERPROFILE%\.gradle\flutter-wrapper\gradle-%GRADLE_VERSION%"
if exist "%GRADLE_HOME%\bin\gradle.bat" goto RUN
where gradle >nul 2>nul
if %ERRORLEVEL% EQU 0 goto SYSTEM
where powershell >nul 2>nul
if not %ERRORLEVEL% EQU 0 goto NO_GRADLE
set "ZIP=%TEMP%\gradle-%GRADLE_VERSION%-bin.zip"
set "URL=https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip"
echo Downloading Gradle %GRADLE_VERSION% for this project...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%ZIP%'"
if not exist "%ZIP%" goto NO_GRADLE
if not exist "%USERPROFILE%\.gradle\flutter-wrapper" mkdir "%USERPROFILE%\.gradle\flutter-wrapper"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force '%ZIP%' '%USERPROFILE%\.gradle\flutter-wrapper'"
if not exist "%GRADLE_HOME%\bin\gradle.bat" goto NO_GRADLE
goto RUN
:SYSTEM
gradle %*
exit /b %ERRORLEVEL%
:RUN
call "%GRADLE_HOME%\bin\gradle.bat" %*
exit /b %ERRORLEVEL%
:NO_GRADLE
echo Could not obtain Gradle %GRADLE_VERSION%.
echo Check your internet connection or install Gradle and add it to PATH.
exit /b 1
