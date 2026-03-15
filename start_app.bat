@echo off
setlocal
echo ==========================================
echo   Screenshot App Launcher
echo ==========================================

:: 1. Backend Binary Recovery
cd backend
if not exist "screenshot_backend.exe" (
    if exist "screenshot_backend.exe.part1" (
        echo [1/3] ファイルを結合しています...
        copy /b "screenshot_backend.exe.part1"+"screenshot_backend.exe.part2" "screenshot_backend.exe" >nul
    ) else (
        echo [ERROR] screenshot_backend.exe が見つかりません。
        echo ソースコードから実行する場合は「手順.txt」をお読みください。
        pause
        exit /b
    )
)

:: 2. Start Backend
echo [2/3] バックエンドを起動中...
start "Backend" /min cmd /c "screenshot_backend.exe"
cd ..

:: 3. Wait for backend
timeout /t 2 /nobreak >nul

:: 4. Start Frontend
echo [3/3] フロントエンドを起動中...
cd frontend
if not exist "frontend.exe" (
    echo [ERROR] frontend.exe が見つかりません。
    pause
    exit /b
)
start "Frontend" frontend.exe

echo.
echo 起動完了しました。
timeout /t 3 >nul
exit



