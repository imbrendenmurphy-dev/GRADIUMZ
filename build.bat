@echo off
rem Build GRADIUMZ -> build\GRADIUMZ.MZT
cd /d "%~dp0"
if not exist build mkdir build
set ASM=tools\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe --nologo
py tools\gen_stage.py build || exit /b 1
py tools\gen_sprites.py build || exit /b 1
py tools\gen_title.py build || exit /b 1
%ASM% --lst=build/gradiumz.lst src/game.asm || exit /b 1
py tools\mkmzt.py build\gradiumz.bin build\GRADIUMZ.MZT GRADIUMZ 1200 1200 || exit /b 1
