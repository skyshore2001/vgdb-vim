*vgdb.txt*	For Vim version 7.3.  Last change: 2013 Feb 22

		    VGdb - Visual Gdb in VIM, v1
		    Liang, Jian - 2013/1

|1| Introduction					|vgdb|
|2| Install						|vgdb-install|
|3| Start vgdb						|:VGdb|
|4| Using vgdb						|vgdb-using|
|5| Preview variable (auto expand)			|vgdb-preview|
|6| VGdb client						|vgdbc|
|7| Contact me						|vgdb-contact|

==============================================================================
*1* Introduction					*vgdb*

VGdb is a perl program that allows the use of vim as a front end to gdb. It
both works on MS Windows and Linux. It both works in gvim and vim.

It opens a VGDB window in vim that allows user to type gdb command directly, 
and gdb output is redirected to this windows.

MSVC-style shortcuts are defined by default (like F5/F10...), and you can 
define how to preview structure like MSVC auto expand feature.

A flash demo in my package helps you quickly go through the vgdb features.

==============================================================================
*2* Install						*vgdb-install*

On MS Windows, you need install Perl (and of course gcc/gdb).
Modify vgdb.bat for your path.
Modify vgdb_install_mswin.bat that actually copy files to your folder.
Run vgdb_install_mswin.bat to copy files.

On Linux, modify path in script vgdb_install and run it. 

Note: 
gvim MUST in the default search path.

My dev envrionment:
Windows: 
Perl 5.8.8 MSWin32-x86
Gdb 7.4 i686-pc-mingw32

Linux:
Perl 5.10.0 for x86_64-linux
Gdb 7.3 x86_64-suse-linux

==============================================================================
*3* Start vgdb							*:VGdb*

* method 1: in vim or gvim, run :VGdb command, e.g. >

	:VGdb
	:VGdb cpp1
	:VGdb cpp1 --tty=/dev/pts/4

You can directly type "gdb" in vi command line as it's set to be the abbreviation of VGdb: >

	:gdb

* method 2: Run vgdb (or vgdb.bat on Widnows)
  it open gvim with the __VGDB__ window for gdb command: >
	
	$ vgdb
	$ vgdb cpp1

==============================================================================
*4*  Using vgdb							*vgdb-using*

A flash demo (__VGDB_DEMO__.htm) in my package helps you quickly go through the
vgdb features. Here are how you can use vgdb:

1) Type gdb command in the __VGDB__ window. Some commands starting with '.'
are known as "vgdb" commands: >

	.c - run or continue
	q  - quit gdb and vgdb
	.p {var} - preview var (according to autoexp.dat); shortcut <C-P>
	.debug={0|1} - disable|enable to show debug info in vgdb
	.ver  - show vgdb version info
	.ju {pos} - jump to position (auto tbreak and allow cross-function)

2) Press Enter or double click in the __VGDB__ window (vim normal mode).

2.1) Jump to a code point or breakpoint: 
if a line contains file/lineno like >
	AddMoney (money=0x7fffffffde20, d=1.1399999999999999) at cpp1.cpp:24
OR >
	breakpoint 2 at 0x4009ad: file cpp1.cpp, line 77.
you can press enter on these lines to go there. Such lines are often
highlighted.

2.2) Jump to a frame of the call stack:
show all frames: >
	bt (or where)
it shows frames like this >
	#0 ...
	#1 ...
double click or press <cr> on the #xx line, it directly goto the frame.

2.3) Derefernece a pointer
A pointer variable is only shown like this: >
	$1 = (SBOString *) 0x7fffffffde10
press enter on this line will get the content just like you run >
	.p *$1

So do struct/class members of pointer type: >
	$2 = {
	  m_strData = 0x603010
	}
press enter on the line of "m_strData" to show this member instead of pointer.

3) Shortcuts

The following shortcuts is applied that is similar to MSVC: 

	<F5> 	- run or continue (.c)
	<S-F5> 	- stop debugging (kill)
	<F10> 	- next
	<F11> 	- step into
	<S-F11> - step out (finish)
	<C-F10>	- run to cursor (tb and c)
	<F9> 	- toggle breakpoint on current line
	\ju or <C-S-F10> - set next statement (tb and jump)
	<C-P> 	- view variable under the cursor (.p)

Note:
If you use vgdb in the vim in a gnome terminal, the <F11> may be conflict with the 
terminal shortcut. You can find menu Edit->Keyboard shortcuts... to disable <F11> in 
the terminal.

All shortcuts will be restored after you quit vgdb.

4) Preview variable via mouse in gvim

The balloon event is supported that you can move you mouse on a variable to
preview the value. It's the same as you input "p var" command or press <C-P>
on the variable.

5) VGdb command

VGdb command has the same effect as you input in the __VGDB__ window. e.g. >

	:VGdb next

6) Execution point jump

VGdb provides simple jump by pressing "\ju" on the new position. More, it
supports cross-function jump. Here's an example: >
	void Fun1()
	{
	..	Fun2();
		printf("OK\n");  // <- you want come there directly 
	}
	void Fun2()
	{
	=>	printf("Fun2\n"); // current execution position
		...
	}

It is in Fun2 but you want to directly jump back to the caller Fun1() and
continue running. You first switch the frame into Fun1, e.g. >
	:VGdb up
Then move the cursor to the new line and press "\ju". VGdb will fix the stack
besides jumping.

==============================================================================
*5* Preview variable (auto expand)			*vgdb-preview*

If a structure/class has many member variables and you are only interested in some
of them, or you want to make the variables more readable, this feature is very
useful. MSVC debugger provides a file named "autoexp.dat" for you to define your
own auto expand rules. VGdb is partially compatible with this file.

You can find an exmaple program cpp1.cpp and the sample autoexp.dat. In the
program, class "SBOString" has a "SBOStringData" pointer and "SBOStringData"
contains the real readable wchar_t string. If you print a SBOString variable,
gdb outputs the pointer value. Now you can define the preview rule in
autoexp.dat: >

	SBOString= str=<m_strData->m_str>, len=<m_strData->m_len>

Then when you print the variable via <C-P> or "p var", it just show >
	str="hello", len=10
as you defined.


Another class MONEY use integer to store data, e.g. 1.1 is stored as 1100000.
To make it more readable, you can define rule: >

	MONEY= <m_data[0]/1e6>

The double value is show when you preview the variable.

Note:
"autoexp.dat" is in your $HOME path or the current path when you start
debugging.

Change in autoexp.dat will immediately take effects.

==============================================================================
*6* VGdb client						*vgdbc*

VGdb is a client-server program via socket that enables it both runs on MS
Windows and Linux. The perl program vgdb is the server program. It also works 
as a client by "-c" option, for example: >

	vgdb -c "b main"

It is called by vim.
The port is auto generated and stored in the envrionment variable *$VGDB_PORT* .
You can directly set the variable to force use some port.

On MS Windows, "vgdb -c" pops up a console window every time as it's a perl
command-line program. Although all functions work, it does not perform perfect. 
So I write vgdbc.c and build out vgdbc.dll that is used by vim (via libcall) 
acting as the client program. With the dll, when you are debugging step by step,
the performance is very good. Note the dll should be put into the search path.

You can test if the DLL works in your vim by: >

	:libcall('vgdbc.dll', 'test', '')
	:libcall('vgdbc.dll', 'tcpcall', 'help')

On Linux, it's built to be the libvgdbc.so and it is optional as the "vgdb -c"
also performs well. Test on Linux: >

	:libcall('libvgdbc.so', 'test', '')

If the binary does not work on your system, you can make it by yourself: >

	$ make 

vgdb auto judge if the lib works in vim. If true, variable *g:vgdb_uselibcall*
is set. You can inspect this variable: >

	echo g:vgdb_uselibcall


==============================================================================
*7* Contact me						*vgdb-contact*

Liang, Jian - skyshore@gmail.com

Thanks to the following softwares that give my ideas: >

	gdbvim (http://www.vim.org/scripts/script.php?script_id=84)
	vimgdb (http://www.vim.org/scripts/script.php?script_id=3039)
	MSVC 
	pyclewn

vim:tw=78:ts=8:sw=8:ft=help:norl:
