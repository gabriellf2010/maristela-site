@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo Node.js nao foi encontrado neste computador.
  echo Instale em https://nodejs.org e execute este arquivo novamente.
  echo.
  pause
  exit /b 1
)
node "%~dp0server.js" %*
if errorlevel 1 (
  echo.
  echo O servidor foi encerrado com erro.
  pause
)
endlocal
