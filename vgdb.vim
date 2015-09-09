"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vgdb - Vim plugin for interface to gdb from cterm
" Maintainer: Liang, Jian (skyshore@gmail.com)
" Thanks to gdbvim and vimgdb.
"
" Feedback welcome.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Prevent multiple loading unless: let force_load=1
if exists("loaded_vgdb") && !exists("force_load")
	finish
endif

let s:ismswin=has('win32')

" ====== config {{{
let loaded_vgdb = 1
let s:vgdb_winheight = 10
let s:vgdb_bufname = "__VGDB__"
let s:vgdb_prompt = '(gdb) '
let s:dbg = 'gdb'

let s:perldbPromptRE = '^\s*DB<\+\d\+>\+\s*'

" used by system-call style
let s:vgdb_client = "vgdb -c" " on MSWin, actually the vgdb.bat is called in the search path
" used by libcall style
let s:vgdb_lib = s:ismswin ? 'vgdbc.dll' : 'libvgdbc.so'
"}}}
" ====== global {{{
let s:bplist = {} " id => {file, line, disabled} that returned by gdb

let s:vgdb_running = 0
let s:debugging = 0
" for pathfix
let s:unresolved_bplist = {} " elem: file_basename => %bplist
"let s:pathMap = {} " unresolved_path => fullpath
let s:nameMap = {} " file_basename => {fullname, pathFixed=0|1}, set by s:getFixedPath()

"let g:vgdb_perl = 0
let g:vgdb_uselibcall=has('libcall')
if g:vgdb_uselibcall
	try
		let s = libcall(s:vgdb_lib, 'test', 'libcall test')
	catch
		let g:vgdb_uselibcall = 0
	endtry
endif

let s:set_disabled_bp = 0
"}}}
" ====== syntax {{{
highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
highlight DisabledBreak guibg=lightred guifg=black ctermbg=lightred ctermfg=black
sign define vgdbBreakpoint linehl=DebugBreak text=B> 
sign define vgdbDisabledbp linehl=DisabledBreak text=b> 
" sign define current linehl=DebugStop
sign define vgdbCurrent linehl=Search text=>> texthl=Search

" highlight vgdbGoto guifg=Blue
hi def link vgdbKey Statement
hi def link vgdbHiLn Statement
hi def link vgdbGoto Underlined
hi def link vgdbPtr Underlined
hi def link vgdbFrame LineNr
hi def link vgdbCmd Macro
"}}}
" ====== toolkit {{{
let s:match = []
function! s:mymatch(expr, pat)
	let s:match = matchlist(a:expr, a:pat)
	return len(s:match) >0
endf

function! s:dirname(file)
	if s:ismswin
		let pos = strridx(a:file, '\')
	else
		let pos = strridx(a:file, '/')
	endif
	return strpart(a:file, 0, pos)
endf

function! s:basename(file)
"	let f = substitute(file, '\', '/', 'g')
	let pos = strridx(a:file, '/')
	if pos<0 && s:ismswin
		let pos = strridx(a:file, '\')
	endif
	return strpart(a:file, pos+1)
endf
"}}}
" ====== app toolkit {{{
function! s:gotoGdbWin()
	if bufname("%") == s:vgdb_bufname
		return
	endif
	let gdbwin = bufwinnr(s:vgdb_bufname)
	if gdbwin == -1
		" if multi-tab or the buffer is hidden
		call s:VGdb_openWindow()
		let gdbwin = bufwinnr(s:vgdb_bufname)
	endif
	exec gdbwin . "wincmd w"
endf

function! s:gotoTgtWin()
	let gdbwin = bufwinnr(s:vgdb_bufname)
	if winnr() == gdbwin
		exec "wincmd p"
	endif
endf

function! s:VGdb_bpkey(file, line)
	return a:file . ":" . a:line
endf

function! s:VGdb_curpos()
	" ???? filename ????
	let file = expand("%:t")
	let line = line(".")
	return s:VGdb_bpkey(file, line)
endf

function! s:placebp(id, line, bnr, disabled)
	let name = (!a:disabled)? "vgdbBreakpoint": "vgdbDisabledbp"
	execute "sign place " . a:id . " name=" . name . " line=" . a:line. " buffer=" . a:bnr
endf

function! s:unplacebp(id)
	execute "sign unplace ". a:id
endf

function! s:setbp(file, lineno, disabled)
	if a:file == "" || a:lineno == 0
		let key = s:VGdb_curpos()
	else
		let key = s:VGdb_bpkey(a:file, a:lineno)
	endif
	let s:set_disabled_bp = a:disabled
	call VGdb("break ".key)
	let s:set_disabled_bp = 0
	" will auto call back s:VGdb_cb_setbp
endf

function! s:delbp(id)
	call VGdb("delete ".a:id)
	call s:VGdb_cb_delbp(a:id)
" 	call VGdb("clear ".key)
endf

"}}}

" ====== functions {{{
" Get ready for communication
function! s:VGdb_openWindow()
    let bufnum = bufnr(s:vgdb_bufname)

    if bufnum == -1
        " Create a new buffer
        let wcmd = s:vgdb_bufname
    else
        " Edit the existing buffer
        let wcmd = '+buffer' . bufnum
    endif

    " Create the tag explorer window
    exe 'silent!  botright ' . s:vgdb_winheight . 'split ' . wcmd
endfunction

" NOTE: this function will be called by vgdb script.
function! VGdb_open()
	" save current setting and restore when vgdb quits via 'so .exrc'
	mk!
	set nocursorline
	set nocursorcolumn

	call s:VGdb_openWindow()

    " Mark the buffer as a scratch buffer
    setlocal buftype=nofile
    setlocal bufhidden=delete
    setlocal noswapfile
    setlocal nowrap
    setlocal nobuflisted
    setlocal nonumber
	setlocal winfixheight
	setlocal cursorline

	setlocal foldcolumn=2
	setlocal foldtext=VGdb_foldTextExpr()
	setlocal foldmarker={,}
	setlocal foldmethod=marker

    augroup VGdbAutoCommand
"	autocmd WinEnter <buffer> if line(".")==line("$") | starti | endif
	autocmd WinLeave <buffer> stopi
	autocmd BufUnload <buffer> call s:VGdb_bufunload()
    augroup end

	call s:VGdb_shortcuts()
	
	let s:vgdb_running = 1

	call VGdb(".init") " get init msg
	starti!
	
	"wincmd p
endfunction

function! s:VGdb_bufunload()
	if s:vgdb_running
		call VGdb('q')
	else
		call s:VGdb_cb_close()
	endif
endfunction

function! s:VGdb_goto(file, line)
	let f = s:getFixedPath(a:file)
	if strlen(f) == 0 
		return
	endif
	call s:gotoTgtWin()
	if bufnr(f) != bufnr("%")
		if &modified || bufname("%") == s:vgdb_bufname
			execute 'new '.f
		else
			execute 'e '.f
		endif

		" resolve bp when entering new buffer
		let base = s:basename(a:file)
		if has_key(s:unresolved_bplist, base)
			let bplist = s:unresolved_bplist[base]
			for [id, bp] in items(bplist)
				call s:VGdb_cb_setbp(id, bp.file, bp.line)
			endfor
			unlet s:unresolved_bplist[base]
		endif
	endif

	execute a:line
	if has('folding')
		silent! foldopen!
	endif
	redraw
"  	call winline()
endf

function! s:getFixedPath(file)
	if ! filereadable(a:file)
		let base = s:basename(a:file)
		if has_key(s:nameMap, base) 
			return s:nameMap[base]
		endif
		if base == expand("%:t")
			let s:nameMap[base] = expand("%:p")
			return s:nameMap[base]
		endif
		let nr = bufnr(base)
		if nr != -1
			let s:nameMap[base] = bufname(nr)
			return s:nameMap[base]
		endif
		return ""
	endif
	return a:file
endf

" breakpoint highlight line may move after you edit the file. 
" this function re-set such BPs (except disables ones) that don't match the actual line.
function! s:refreshBP()
	" get sign list
	lan message C
	redir => a
	sign place
	redir end

" e.g.
" 	Signs for cpp1.cpp:
" 		line=71  id=1  name=disabledbp
" 		line=73  id=1  name=disabledbp
" 	Signs for /usr/share/vim/current/doc/eval.txt:
" 		line=4  id=1  name=bp1

	let confirmed = 0
	for line in split(a, "\n")
		if s:mymatch(line, '\v\s+line\=(\d+)\s+id\=(\d+)') && has_key(s:bplist, s:match[2])
			let lineno = s:match[1]
			let id = s:match[2]
			let bp = s:bplist[id]
			if bp.line != lineno
				if !confirmed 
					let choice = confirm("Breakpoint position changes. Refresh now? (Choose No if the source code does not match the executable.)", "&Yes\n&No")
					if choice != 1
						break
					endif
					let confirmed = 1
				endif
				call s:delbp(id)
				call s:setbp(bp.file, lineno, bp.disabled)
			endif
		endif
	endfor
endf

function! s:setDebugging(val)
	if s:debugging != a:val
		if s:debugging == 0  " 0 -> 1: run/attach
			call s:refreshBP()
		endif
		let s:debugging = a:val
	endif
endf

"====== callback {{{
let s:callmap={ 
	\'setdbg': 's:setdbg', 
	\'setbp': 's:VGdb_cb_setbp', 
	\'delbp': 's:VGdb_cb_delbp', 
	\'setpos': 's:VGdb_cb_setpos', 
	\'delpos': 's:VGdb_cb_delpos', 
	\'exe': 's:VGdb_cb_exe', 
	\'quit': 's:VGdb_cb_close' 
\ }

function! s:setdbg(dbg)
	let s:dbg = a:dbg
	if s:dbg == "perldb"
		let s:vgdb_prompt = "  DB<1> "
	elseif s:dbg == 'gdb'
		let s:vgdb_prompt = "(gdb) "
	endif
endf

function! s:VGdb_cb_setbp(id, file, line, ...)
	if has_key(s:bplist, a:id)
		return
	endif
	let hint = a:0>0 ? a:1 : ''
	let bp = {'file': a:file, 'line': a:line, 'disabled': s:set_disabled_bp}
	let f = s:getFixedPath(a:file)
	if (hint == 'pending' && bufnr(a:file) == -1) || strlen(f)==0
		let base = s:basename(a:file)
		if !has_key(s:unresolved_bplist, base)
			let s:unresolved_bplist[base] = {}
		endif
		let bplist = s:unresolved_bplist[base]
		let bplist[a:id] = bp
		return
	endif
	call s:VGdb_goto(f, a:line)
"	execute "sign unplace ". a:id
	if bp.disabled
		call VGdb("disable ".a:id)
	endif
	call s:placebp(a:id, a:line, bufnr(f), bp.disabled)
	let s:bplist[a:id] = bp
endfunction

function! s:VGdb_cb_delbp(id)
	if has_key(s:bplist, a:id)
		unlet s:bplist[a:id]
		call s:unplacebp(a:id)
	endif
endf

let s:last_id = 0
function! s:VGdb_cb_setpos(file, line)
	if a:line <= 0
		call s:setDebugging(1)
		return
	endif

	let s:nameMap[s:basename(a:file)] = a:file
	call s:VGdb_goto(a:file, a:line)
	call s:setDebugging(1)

	" place the next line before unplacing the previous 
	" otherwise display will jump
	let newid = (s:last_id+1) % 2
	execute "sign place " .  (10000+newid) ." name=vgdbCurrent line=".a:line." buffer=".bufnr(a:file)
	execute "sign unplace ". (10000+s:last_id)
	let s:last_id = newid
endf

function! s:VGdb_cb_delpos()
	execute "sign unplace ". (10000+s:last_id)
	call s:setDebugging(0)
endf

function! s:VGdb_cb_exe(cmd)
	exe a:cmd
endf

function! s:VGdb_cb_close()
	if !s:vgdb_running
		return
	endif

	let s:vgdb_running = 0
	let s:bplist = {}
	let s:unresolved_bplist = {}
	sign unplace *
	if has('balloon_eval')
		set bexpr&
	endif

	" If gdb window is open then close it.
	call s:gotoGdbWin()
	quit

    silent! autocmd! VGdbAutoCommand
	if s:ismswin
		so _exrc
	else
		so .exrc
	endif
endf

"}}}

function! VGdb_call(cmd)
	let usercmd = a:cmd
	if exists("g:vgdb_useperl") && g:vgdb_useperl
		perl <<EOF
	open O, ">tmp1";
	select O;
	my $usercmd = VIM::Eval("usercmd");
	{
	local @ARGV = ('-c', $usercmd);
	do "d:/prog2/vgdb/vgdb";
	}
	close O;
EOF
		let lines = readfile("tmp1")
	elseif exists("g:vgdb_uselibcall") && g:vgdb_uselibcall
		let lines = libcall(s:vgdb_lib, "tcpcall", usercmd)
	else
		let usercmd = substitute(usercmd, '["$]', '\\\0', 'g')
		let lines = system(s:vgdb_client . " \"" . usercmd . "\"")
	endif
	return lines
endf

" mode: i|n|c|<empty>
" i - input command in VGDB window and press enter
" n - press enter (or double click) in VGDB window
" c - run Gdb command
function! VGdb(cmd, ...)  " [mode]
	let usercmd = a:cmd
	let mode = a:0>0 ? a:1 : ''

	if s:vgdb_running == 0
" 		let is_loadfile = 0
" 		let is_loadfile = 1
		if !exists('$VGDB_PORT')
			if s:ismswin && g:vgdb_uselibcall
				" !!!! windows gvim has bug on libcall() - libcall cannot access
				" envvar defined in VIM. So here I make the port the same as
				" the one in the file vgdbc.c
				" LIMITATION: 1 debugging at one time on MSWin with libcall
				let $VGDB_PORT = 30899
			else
				let $VGDB_PORT= 30000 + reltime()[1] % 10000
			endif
		endif
		if s:ismswin
			" !!! "!start" is different from "! start"
			let startcmd = "!start vgdb.bat -vi " . usercmd
		else
			if !has('gui')
				let startcmd = "!vgdb -vi ".usercmd." &>/dev/null &"
			else
				let startcmd = "!vgdb -vi ".usercmd." &"
			endif
		endif
		exe 'silent '.startcmd
		call VGdb_open()
" 		if is_loadfile
" 			sleep 200 m
" 			call VGdb("@tb main; r")
" 			return
" 		endif
		return
	endif

	if s:vgdb_running == 0
		echo "vgdb is not running"
		return
	endif

	let curwin = winnr()
	let stayInTgtWin = 0
	if s:dbg == 'gdb' && usercmd =~ '^\s*(gdb)' 
		let usercmd = substitute(usercmd, '^\s*(gdb)\s*', '', '')
	elseif s:dbg == 'perldb' && usercmd =~ '^\s*DB<'
		let usercmd = substitute(usercmd, s:perldbPromptRE, '', '')
	elseif mode == 'i'
		" trim left and clean the search word
		s/^\s\+//e
		let @/=''
		if line('.') != line('$')
			call append('$', s:vgdb_prompt . usercmd)
			$
		else
			exe "normal I" . s:vgdb_prompt
		endif
	endif
	" goto frame
	" 	i br (info breakpoints)
	" 	#0  0x00007fc54f6955e7 in recv () from /lib64/libpthread.so.0
	if s:mymatch(usercmd, '\v^#(\d+)') && s:debugging
		let usercmd = "@frame " . s:match[1]
		let stayInTgtWin = 1
		let mode = 'n'
	
	" goto thread and show frames
	" 	i thr (info threads)
	" 	7    Thread 0x7fc54032b700 (LWP 25787) "java" 0x00007fc54f6955e7 in recv () from /lib64/libpthread.so.0
	elseif s:mymatch(usercmd, '\v^\s+(\d+)\s+Thread ') && s:debugging
		let usercmd = "@thread " . s:match[1] . "; bt"

	" Breakpoint 1, TmScrParser::Parse (this=0x7fffffffbbb0) at ../../BuildBuilder/CreatorDll/TmScrParser.cpp:64
	" Breakpoint 14 at 0x7ffff7bbeec1: file ../../BuildBuilder/CreatorDll/RDLL_SboP.cpp, line 111.
	" Breakpoint 6 (/home/builder/depot/BUSMB_B1/SBO/9.01_DEV/BuildBuilder/CreatorDll/RDLL_SboP.cpp:92) pending.
	" Breakpoint 17 at 0x7fc3f1f8b523: B1FileWriter.cpp:268. (2 locations)
	elseif s:mymatch(usercmd, '\v<at %(0x\S+ )?(..[^:]*):(\d+)') || s:mymatch(usercmd, '\vfile ([^,]+), line (\d+)') || s:mymatch(usercmd, '\v\((..[^:]*):(\d+)\)')
		call s:VGdb_goto(s:match[1], s:match[2])
		return
	" for perldb:
	"   @ = main::getElems(...) called from file `./parse_vc10.pl' line 207
	" Note: On windows: perldb uses "'" rather than "`"
	" 	DB::eval called at /usr/lib/perl5/5.10.0/perl5db.pl line 3436
	"   syntax error at (eval 9)[C:/Perl/lib/perl5db.pl:646] line 2, near "frame 0"
	elseif s:mymatch(usercmd, '\v from file [`'']([^'']+)'' line (\d+)') || s:mymatch(usercmd, '\v at ([^ ]+) line (\d+)') || s:mymatch(usercmd, '\v at \(eval \d+\)(..[^:]+):(\d+)')
		call s:VGdb_goto(s:match[1], s:match[2])
		return
	elseif mode == 'n'  " mode n: jump to source or current callstack, dont exec other gdb commands
		call VGdb_expandPointerExpr()
		return
	endif

	call s:gotoGdbWin()
	if getline("$") =~ '^\s*$'
		$delete
	endif

	let lines = split(VGdb_call(usercmd), "\n")

	for line in lines
		let hideline = 0
		if line =~ '^vi:'
			let cmd = substitute(line, '\v^vi:(\w+)', '\=s:callmap[submatch(1)]', "")
			let hideline = 1
			exec 'call ' . cmd
			if line =~ ':quit()'
				return
			endif
		endif
		if !hideline
			call s:gotoGdbWin()
			" bugfix: '{0x123}' is wrong treated when foldmethod=marker 
			let line = substitute(line, '{\ze\S', '{ ', 'g')
			call append(line("$"), line)
			$
			redraw
			"let output_{out_count} = substitute(line, "", "", "g")
		endif
	endfor
	if s:dbg == 'perldb' && line =~ s:perldbPromptRE
		let s:vgdb_prompt = line
	endif

	if mode == 'i' && !stayInTgtWin
		call s:gotoGdbWin()
		if getline('$') != s:vgdb_prompt
			call append('$', s:vgdb_prompt)
		endif
		$
		starti!
	endif

	if stayInTgtWin
		call s:gotoTgtWin()
	elseif curwin != winnr()
		exec curwin."wincmd w"
	endif
endf

" Toggle breakpoints
function! VGdb_toggle(forDisable)
	call s:gotoTgtWin()
	let file = expand("%:t")
	let line = line('.')
	for [id, bp] in items(s:bplist)
		if bp.line == line && s:basename(bp.file) == file
			if ! a:forDisable
				call s:delbp(id)
			else
				if bp.disabled
					call VGdb("enable ".id)
				else
					call VGdb("disable ".id)
				endif
				let bp.disabled = !bp.disabled
				call s:placebp(id, bp.line, bufnr("%"), bp.disabled)
			endif
			return
		endif
	endfor
	if ! a:forDisable
		call s:setbp('', 0, 0) " set on current position
	endif
endf

function! VGdb_jump()
	call s:gotoTgtWin()
	let key = s:VGdb_curpos()
"	call VGdb("@tb ".key." ; ju ".key)
"	call VGdb("set $rbp1=$rbp; set $rsp1=$rsp; @tb ".key." ; ju ".key . "; set $rsp=$rsp1; set $rbp=$rbp1")
	call VGdb(".ju ".key)
endf

function! VGdb_runToCursur()
	call s:gotoTgtWin()
	let key = s:VGdb_curpos()
	call VGdb("@tb ".key." ; c")
endf

function! s:VGdb_shortcuts()

	" syntax
	syn keyword vgdbKey Function Breakpoint Catchpoint 
	syn match vgdbFrame /\v^#\d+ .*/ contains=vgdbGoto
	syn match vgdbGoto /\v<at [^()]+:\d+|file .+, line \d+/
	syn match vgdbCmd /^(gdb).*/
	syn match vgdbPtr /\v(^|\s+)\zs\$?\w+ \=.{-0,} 0x\w+/
	" highlight the whole line for 
	" returns for info threads | info break | finish | watchpoint
	syn match vgdbHiLn /\v^\s*(Id\s+Target Id|Num\s+Type|Value returned is|(Old|New) value =|Hardware watchpoint).*$/

	" syntax for perldb
	syn match vgdbCmd /^\s*DB<.*/
"	syn match vgdbFrame /\v^#\d+ .*/ contains=vgdbGoto
	syn match vgdbGoto /\v from file ['`].+' line \d+/
	syn match vgdbGoto /\v at ([^ ]+) line (\d+)/
	syn match vgdbGoto /\v at \(eval \d+\)..[^:]+:\d+/

	
	" shortcut in VGDB window
    inoremap <buffer> <silent> <CR> <c-o>:call VGdb(getline('.'), 'i')<cr>
	imap <buffer> <silent> <2-LeftMouse> <cr>
	imap <buffer> <silent> <kEnter> <cr>

    nnoremap <buffer> <silent> <CR> :call VGdb(getline('.'), 'n')<cr>
	nmap <buffer> <silent> <2-LeftMouse> <cr>
	nmap <buffer> <silent> <kEnter> <cr>

	inoremap <buffer> <silent> <TAB> <C-X><C-L>
	"nnoremap <buffer> <silent> : <C-W>p:

	nmap <silent> <F9>	 :call VGdb_toggle(0)<CR>
	nmap <silent> <C-F9>	 :call VGdb_toggle(1)<CR>
	nmap <silent> <Leader>ju	 :call VGdb_jump()<CR>
	nmap <silent> <C-S-F10>		 :call VGdb_jump()<CR>
	nmap <silent> <C-F10> :call VGdb_runToCursur()<CR>
"	nmap <silent> <F6>   :call VGdb("run")<CR>
	nmap <silent> <C-P>	 :VGdb .p <C-R><C-W><CR>
	vmap <silent> <C-P>	 y:VGdb .p <C-R>0<CR>
	nmap <silent> <Leader>pr	 :VGdb p <C-R><C-W><CR>
	vmap <silent> <Leader>pr	 y:VGdb p <C-R>0<CR>
	nmap <silent> <Leader>bt	 :VGdb bt<CR>

	map <silent> <F5>    :VGdb .c<cr>
	map <silent> <S-F5>  :VGdb k<cr>
	map <silent> <F10>   :VGdb n<cr>
	map <silent> <F11>   :VGdb s<cr>
	map <silent> <S-F11> :VGdb finish<cr>

	amenu VGdb.Toggle\ breakpoint<tab>F9			:call VGdb_toggle(0)<CR>
	amenu VGdb.Run/Continue<tab>F5 					:VGdb c<CR>
	amenu VGdb.Step\ into<tab>F11					:VGdb s<CR>
	amenu VGdb.Next<tab>F10							:VGdb n<CR>
	amenu VGdb.Step\ out<tab>Shift-F11				:VGdb finish<CR>
	amenu VGdb.Run\ to\ cursor<tab>Ctrl-F10			:call VGdb_runToCursur()<CR>
	amenu VGdb.Stop\ debugging\ (Kill)<tab>Shift-F5	:VGdb k<CR>
	amenu VGdb.-sep1- :

	amenu VGdb.Show\ callstack<tab>\\bt				:call VGdb("where")<CR>
	amenu VGdb.Set\ next\ statement\ (Jump)<tab>Ctrl-Shift-F10\ or\ \\ju 	:call VGdb_jump()<CR>
	amenu VGdb.Top\ frame 						:call VGdb("frame 0")<CR>
	amenu VGdb.Callstack\ up 					:call VGdb("up")<CR>
	amenu VGdb.Callstack\ down 					:call VGdb("down")<CR>
	amenu VGdb.-sep2- :

	amenu VGdb.Preview\ variable<tab>Ctrl-P		:VGdb .p <C-R><C-W><CR> 
	amenu VGdb.Print\ variable<tab>\\pr			:VGdb p <C-R><C-W><CR> 
	amenu VGdb.Show\ breakpoints 				:VGdb info breakpoints<CR>
	amenu VGdb.Show\ locals 					:VGdb info locals<CR>
	amenu VGdb.Show\ args 						:VGdb info args<CR>
	amenu VGdb.Quit			 					:VGdb q<CR>

	if has('balloon_eval')
		set bexpr=VGdb_balloonExpr()
		set balloondelay=500
		set ballooneval
	endif
endf

function! VGdb_balloonExpr()
	return VGdb_call('.p '.v:beval_text)
" 	return 'Cursor is at line ' . v:beval_lnum .
" 		\', column ' . v:beval_col .
" 		\ ' of file ' .  bufname(v:beval_bufnr) .
" 		\ ' on word "' . v:beval_text . '"'
endf

function! VGdb_foldTextExpr()
	return getline(v:foldstart) . ' ' . substitute(getline(v:foldstart+1), '\v^\s+', '', '') . ' ... (' . (v:foldend-v:foldstart-1) . ' lines)'
endfunction

" if the value is a pointer ( var = 0x...), expand it by "VGdb .p *var"
" e.g. $11 = (CDBMEnv *) 0x387f6d0
" e.g.  
" (CDBMEnv) $22 = {
"  m_pTempTables = 0x37c6830,
"  ...
" }
function! VGdb_expandPointerExpr()
	if ! s:mymatch(getline('.'), '\v((\$|\w)+) \=.{-0,} 0x')
		return 0
	endif
	let cmd = s:match[1]
	let lastln = line('.')
	while 1
		normal [z
		if line('.') == lastln
			break
		endif
		let lastln = line('.')

		if ! s:mymatch(getline('.'), '\v(([<>$]|\w)+) \=')
			return 0
		endif
		" '<...>' means the base class. Just ignore it. Example:
" (OBserverDBMCInterface) $4 = {
"   <__DBMC_ObserverA> = {
"     members of __DBMC_ObserverA:
"     m_pEnv = 0x378de60
"   }, <No data fields>}

		if s:match[1][0:0] != '<' 
			let cmd = s:match[1] . '.' . cmd
		endif
	endwhile 
"	call append('$', cmd)
	exec "VGdb .p *" . cmd
	if foldlevel('.') > 0
		" goto beginning of the fold and close it
		normal [zzc
		" ensure all folds for this var are closed
		foldclose!
	endif
	return 1
endf
"}}}

" ====== commands {{{
command! -nargs=* -complete=file VGdb :call VGdb(<q-args>)
ca gdb VGdb
ca Gdb VGdb
" directly show result; must run after VGdb is running
command! -nargs=* -complete=file VGdbcall :echo VGdb_call(<q-args>)
"}}}
" vim: set foldmethod=marker :
