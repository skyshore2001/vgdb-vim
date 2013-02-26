"""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vgdb - Vim plugin for interface to gdb from cterm
" Last change: v1.0
" Maintainer: Liang, Jian (skyshore@gmail.com)
" Thanks to gdbvim and vimgdb.
"
" Feedback welcome.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Prevent multiple loading, allow commenting it out
if exists("loaded_vgdb")
	finish
endif

let s:ismswin=has('win32')

" ====== config
let loaded_vgdb = 1
let s:vgdb_winheight = 10
let s:vgdb_bufname = "__VGDB__"

" used by system-call style
let s:vgdb_client = "vgdb -c" " on MSWin, actually the vgdb.bat is called in the search path
" used by libcall style
let s:vgdb_lib = s:ismswin ? 'vgdbc.dll' : 'libvgdbc.so'

" ====== global
let s:bplist = {} " id => {file, line} that returned by gdb

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

" ====== syntax
" This used to be in VGdb_open, but older vims crashed on it
highlight DebugBreak guibg=darkred guifg=white ctermbg=darkred ctermfg=white
" highlight DebugStop guibg=lightgreen guifg=white ctermbg=lightgreen ctermfg=white
sign define breakpoint linehl=DebugBreak
" sign define current linehl=DebugStop
sign define current linehl=Search text=>> texthl=Search

" highlight vgdbGoto guifg=Blue
hi def link vgdbKey Statement
hi def link vgdbGoto Type
hi def link vgdbFrame LineNr

"===== toolkit {{{
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
	exec gdbwin . "wincmd w"
endf

function! s:gotoTgtWin()
	let gdbwin = bufwinnr(s:vgdb_bufname)
	if winnr() == gdbwin
		exec "wincmd p"
	endif
endf
"}}}

" Get ready for communication
function! VGdb_open()
	" save current setting and restore when vgdb quits via 'so .exrc'
	mk!
	set nocursorline
	set nocursorcolumn

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

    " Mark the buffer as a scratch buffer
    setlocal buftype=nofile
    setlocal bufhidden=delete
    setlocal noswapfile
    setlocal nowrap
    setlocal nobuflisted
    setlocal nonumber
	setlocal winfixheight
	setlocal cursorline

    augroup VGdbAutoCommand
"	autocmd WinEnter <buffer> if line(".")==line("$") | starti | endif
	autocmd WinLeave <buffer> stopi
	autocmd BufUnload <buffer> call s:VGdb_bufunload()
    augroup end

	call s:VGdb_shortcuts()
	call append(0, "(gdb)")
	starti
	
	let s:vgdb_running = 1

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
		if &modified 
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

	"silent! foldopen!
	execute a:line
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

"====== callback {{{
let s:callmap={ 
	\'setbp': 's:VGdb_cb_setbp', 
	\'delbp': 's:VGdb_cb_delbp', 
	\'setpos': 's:VGdb_cb_setpos', 
	\'delpos': 's:VGdb_cb_delpos', 
	\'exe': 's:VGdb_cb_exe', 
	\'quit': 's:VGdb_cb_close' 
\}

function! s:VGdb_cb_setbp(id, file, line, ...)
	if has_key(s:bplist, a:id)
		return
	endif
	let hint = a:0>0 ? a:1 : ''
	let bp = {'file': a:file, 'line': a:line}
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
	execute "sign place " .  a:id ." name=breakpoint line=".a:line." buffer=".bufnr(f)
	let s:bplist[a:id] = bp
endfunction

function! s:VGdb_cb_delbp(id)
	if has_key(s:bplist, a:id)
		unlet s:bplist[a:id]
		execute "sign unplace ". a:id
	endif
endf

let s:last_id = 0
function! s:VGdb_cb_setpos(file, line)
	let s:nameMap[s:basename(a:file)] = a:file
	call s:VGdb_goto(a:file, a:line)
	let s:debugging = 1

	" place the next line before unplacing the previous 
	" otherwise display will jump
	let newid = (s:last_id+1) % 2
	execute "sign place " .  (10000+newid) ." name=current line=".a:line." buffer=".bufnr(a:file)
	execute "sign unplace ". (10000+s:last_id)
	let s:last_id = newid
endf

function! s:VGdb_cb_delpos()
	execute "sign unplace ". (10000+s:last_id)
	let s:debugging = 0
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
	if s:mymatch(usercmd, '\v#(\d+)') && s:debugging
		let usercmd = "@frame " . s:match[1]
		let stayInTgtWin = 1

	" Breakpoint 1, TmScrParser::Parse (this=0x7fffffffbbb0) at ../../BuildBuilder/CreatorDll/TmScrParser.cpp:64
	" Breakpoint 14 at 0x7ffff7bbeec1: file ../../BuildBuilder/CreatorDll/RDLL_SboP.cpp, line 111.
	" Breakpoint 6 (/home/builder/depot/BUSMB_B1/SBO/9.01_DEV/BuildBuilder/CreatorDll/RDLL_SboP.cpp:92) pending.
	elseif s:mymatch(usercmd, '\vat (..[^:]*):(\d+)') || s:mymatch(usercmd, '\vfile ([^,]+), line (\d+)') || s:mymatch(usercmd, '\v\((..[^:]*):(\d+)\)')
		call s:VGdb_goto(s:match[1], s:match[2])
		return
	elseif mode == 'n'  " mode n: jump to source or current callstack, dont exec other gdb commands
		return
	elseif usercmd == "c" && s:debugging == 0
		let usercmd = "r"
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
			call append(line("$"), line)
			$
			redraw
			"let output_{out_count} = substitute(line, "", "", "g")
		endif
	endfor

	if mode == 'i' && !stayInTgtWin
		call s:gotoGdbWin()
		normal Go
		starti
	endif

	if stayInTgtWin
		call s:gotoTgtWin()
	elseif curwin != winnr()
		exec curwin."wincmd w"
	endif
endf

function! s:VGdb_curpos()
	" ???? filename ????
	let file = expand("%:t")
	let line = line(".")
	return file . ":" . line
endf

" Toggle breakpoints
function! VGdb_toggle()
	call s:gotoTgtWin()
	let file = expand("%:t")
	let line = line('.')
	let key = s:VGdb_curpos()
	for [id, bp] in items(s:bplist)
		if bp.line == line && s:basename(bp.file) == file
			call s:VGdb_cb_delbp(id)
			call VGdb("clear ".key)
			return
		endif
	endfor
	call VGdb("break ".key)
endf

function! VGdb_jump()
	call s:gotoTgtWin()
	let key = s:VGdb_curpos()
	call VGdb("tb ".key." ; ju ".key)
endf

function! VGdb_runToCursur()
	call s:gotoTgtWin()
	let key = s:VGdb_curpos()
	call VGdb("tb ".key." ; c")
endf

function! s:VGdb_shortcuts()

	" syntax
	syn keyword vgdbKey Function Breakpoint Num Type Disp Enb Address What
	syn match vgdbFrame /\v^#\d+/
	syn match vgdbGoto /\v^.* (at .+:\d+|file .+, line \d+).*$/

	" shortcut in VGDB window
    inoremap <buffer> <silent> <CR> <c-o>:call VGdb(getline('.'), 'i')<cr>
    nnoremap <buffer> <silent> <CR> :call VGdb(getline('.'), 'n')<cr>
	nnoremap <buffer> <silent> <2-LeftMouse> :call VGdb(getline('.'), 'n')<cr>
	inoremap <buffer> <silent> <2-LeftMouse> <c-o>:call VGdb(getline('.'), 'n')<cr>
	inoremap <buffer> <silent> <TAB> <C-P>
	"nnoremap <buffer> <silent> : <C-W>p:

	nmap <silent> <F9>	 :call VGdb_toggle()<CR>
	nmap <silent> <Leader>ju	 :call VGdb_jump()<CR>
	nmap <silent> <C-S-F10>		 :call VGdb_jump()<CR>
	nmap <silent> <C-F10> :call VGdb_runToCursur()<CR>
"	nmap <silent> <F6>   :call VGdb("run")<CR>
	nmap <silent> <C-P>	 :VGdb p <C-R><C-W><CR>
	vmap <silent> <C-P>	 y:VGdb p <C-R>0<CR>

	map <silent> <F5>    :VGdb c<cr>
	map <silent> <S-F5>  :VGdb k<cr>
	map <silent> <F10>   :VGdb n<cr>
	map <silent> <F11>   :VGdb s<cr>
	map <silent> <S-F11> :VGdb finish<cr>

	amenu VGdb.Toggle\ breakpoint<tab>F9			:call VGdb_toggle()<CR>
	amenu VGdb.Run/Continue<tab>F5 					:VGdb c<CR>
	amenu VGdb.Step\ into<tab>F11					:VGdb s<CR>
	amenu VGdb.Next<tab>F10							:VGdb n<CR>
	amenu VGdb.Step\ out<tab>Shift-F11				:VGdb finish<CR>
	amenu VGdb.Run\ to\ cursor<tab>Ctrl-F10			:call VGdb_runToCursur()<CR>
	amenu VGdb.Stop\ debugging\ (Kill)<tab>Shift-F5	:VGdb k<CR>
	amenu VGdb.-sep1- :

	amenu VGdb.Show\ callstack					:call VGdb("where")<CR>
	amenu VGdb.Set\ next\ statement\ (Jump)<tab>Ctrl-Shift-F10\ or\ \\ju 	:call VGdb_jump()<CR>
	amenu VGdb.Top\ frame 						:call VGdb("#0")<CR>
	amenu VGdb.Callstack\ up 					:call VGdb("up")<CR>
	amenu VGdb.Callstack\ down 					:call VGdb("down")<CR>
	amenu VGdb.-sep2- :

	amenu VGdb.Print\ variable<tab>Ctrl-P		:VGdb print <C-R><C-W><CR> 
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
	return VGdb_call('p '.v:beval_text)
" 	return 'Cursor is at line ' . v:beval_lnum .
" 		\', column ' . v:beval_col .
" 		\ ' of file ' .  bufname(v:beval_bufnr) .
" 		\ ' on word "' . v:beval_text . '"'
endf

command -nargs=* -complete=file VGdb :call VGdb(<q-args>)
ca gdb VGdb
ca Gdb VGdb
" directly show result; must run after VGdb is running
command -nargs=* -complete=file VGdbcall :echo VGdb_call(<q-args>)

