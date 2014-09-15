@echo off

setlocal enableextensions enabledelayedexpansion 

::set BIN=c:\windows\system32
set BIN=d:\tempbin
set VIMFILES=D:\vim\vimfiles

gdb -v >NUL 2>NUL
if not %errorlevel%==0 (
	echo ERROR: 'gdb' does not in binary path!
	goto :EOF
)

gvim -c q 2>NUL
if not %errorlevel%==0 (
	echo ERROR: 'gvim' does not in binary path!
	goto :EOF
)

set PERL=perl
:try_perl
%PERL% -e0 2>NUL
if not %errorlevel%==0 (
	set opt=
	set /p opt="Full path for perl.exe? "
	if not "!opt!"=="" set PERL=!opt!
	goto try_perl
)

set opt=
set /p opt="binary dir? (%BIN%) "
if not "%opt%"=="" set BIN=%opt%

set opt=
set /p opt="vimfiles dir? (%VIMFILES%) "
if not "%opt%"=="" set VIMFILES=%opt%

rem vgdb.bat and vgdbc.dll MUST in the search path, e.g. c:\windows\system32
echo @%PERL% %CD%\vgdb %* > %BIN%\vgdb.bat
:: copy vgdb.bat %BIN%\
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
