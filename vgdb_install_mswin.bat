@echo off

::set BIN=c:\windows\system32
set BIN=d:\tempbin
set VIMFILES=D:\vim\vimfiles

rem vgdb.bat and vgdbc.dll MUST in the search path, e.g. c:\windows\system32
copy vgdb.bat %BIN%\
copy vgdbc.dll %BIN%\

rem copy the plugin and doc to your vim folder
copy vgdb.vim %VIMFILES%\plugin\vgdb.vim
copy __README__.txt %VIMFILES%\doc\vgdb.txt
gvim -c "helptags %VIMFILES%\doc | h vgdb.txt | only"

pause
