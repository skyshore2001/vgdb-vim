@echo off

setlocal
::set BIN=c:\windows\system32
set BIN=d:\tempbin
set VIMFILES=D:\vim\vimfiles

set opt=
set /p opt="binary dir? (%BIN%) "
if not "%opt%"=="" set BIN=%opt%

set opt=
set /p opt="vimfiles dir? (%VIMFILES%) "
if not "%opt%"=="" set VIMFILES=%opt%

rem vgdb.bat and vgdbc.dll MUST in the search path, e.g. c:\windows\system32
copy vgdb.bat %BIN%\
copy vgdbc.dll %BIN%\

rem copy the plugin and doc to your vim folder
copy vgdb.vim %VIMFILES%\plugin\vgdb.vim
copy __README__.txt %VIMFILES%\doc\vgdb.txt

set opt=y
set /p opt="view doc? (=y/n) "
if "%opt%"=="y" (
	gvim -c "helptags %VIMFILES%\doc | h vgdb.txt | only"
) else (
	gvim -c "helptags %VIMFILES%\doc | q"
	echo done.
)

pause
