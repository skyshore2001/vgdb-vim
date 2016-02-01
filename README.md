# vgdb

VGdb is a perl application that enables vim as the front end of a debugger
like gdb and perldb.
It both works on MS Windows and Linux. It both works in gvim and vim.

It opens a VGDB window in vim that allows user to type gdb command directly, 
and gdb output is redirected to this windows.

MSVC-style shortcuts are defined by default (like F5/F10...), and you can 
define how to preview structure like MSVC auto expand feature.

Screenshot:
![Screenshot](https://github.com/skyshore2001/vgdb-vim/raw/master/demo/screenshot.png)

A flash demo in my package helps you quickly go through the vgdb features.

**For detail, read this vim help document: __README__.txt**

## Install

On Linux, run vgdb_install and specify path.

	# sh vgdb_install

On MS Windows, you need install Perl (and of course gcc/gdb).
Run vgdb_install_mswin.bat that actually copy files to your folder.

Note: 
- gvim MUST in the default search path.

My dev environment:
- Windows: 
 - Perl 5.8.8 MSWin32-x86
 - Gdb 7.4 i686-pc-mingw32
- Linux:
 - Perl 5.10.0 for x86_64-linux
 - Gdb 7.3 x86_64-suse-linux

## Quick usage

In vim or gvim, run :VGdb command, e.g.

	:VGdb
	:VGdb cpp1
	:VGdb cpp1 --tty=/dev/pts/4

To debug a perl program:

	:VGdb hello.pl

The following shortcuts is applied that is similar to MSVC: 

	<F5> 	- run or continue
	<S-F5> 	- stop debugging (kill)
	<F10> 	- next
	<F11> 	- step into
	<S-F11> - step out (finish)
	<C-F10>	- run to cursor (tb and c)
	<F9> 	- toggle breakpoint on current line
	<C-F9> 	- toggle enable/disable breakpoint on current line
	\ju or <C-S-F10> - set next statement (tb and jump)
	<C-P> 	- view variable under the cursor (.p)

