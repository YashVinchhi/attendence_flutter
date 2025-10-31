@echo off
REM Copies assets/LOGO.png to Android mipmap folders and web icons for a quick icon update.
SET ROOT=%~dp0..\
SET ASSET=%ROOT%assets\LOGO.png

if not exist "%ASSET%" (
  echo ERROR: %ASSET% not found. Please create assets\LOGO.png (1024x1024 recommended).
  exit /b 1
)

echo Copying icon to Android mipmap folders...
if not exist "%ROOT%android\app\src\main\res\mipmap-mdpi" mkdir "%ROOT%android\app\src\main\res\mipmap-mdpi"
if not exist "%ROOT%android\app\src\main\res\mipmap-hdpi" mkdir "%ROOT%android\app\src\main\res\mipmap-hdpi"
if not exist "%ROOT%android\app\src\main\res\mipmap-xhdpi" mkdir "%ROOT%android\app\src\main\res\mipmap-xhdpi"
if not exist "%ROOT%android\app\src\main\res\mipmap-xxhdpi" mkdir "%ROOT%android\app\src\main\res\mipmap-xxhdpi"
if not exist "%ROOT%android\app\src\main\res\mipmap-xxxhdpi" mkdir "%ROOT%android\app\src\main\res\mipmap-xxxhdpi"

xcopy /y "%ASSET%" "%ROOT%android\app\src\main\res\mipmap-mdpi\ic_launcher.png" >nul
xcopy /y "%ASSET%" "%ROOT%android\app\src\main\res\mipmap-hdpi\ic_launcher.png" >nul
xcopy /y "%ASSET%" "%ROOT%android\app\src\main\res\mipmap-xhdpi\ic_launcher.png" >nul
xcopy /y "%ASSET%" "%ROOT%android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png" >nul
xcopy /y "%ASSET%" "%ROOT%android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png" >nul

echo Copying icon to web icons...
if not exist "%ROOT%web\icons" mkdir "%ROOT%web\icons"
xcopy /y "%ASSET%" "%ROOT%web\icons\Icon-192.png" >nul
xcopy /y "%ASSET%" "%ROOT%web\icons\Icon-512.png" >nul

echo Finished copying. Now run:
echo   flutter clean && flutter pub get && flutter run
echo And uninstall the existing app from your device/emulator to see the new icon.
pause
