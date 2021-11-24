" Implementations of the functions described in autodelim.txt.
"
" 2021 Oct 21 - Written by Kenny Lam.

" Dictionary that contains the delimiters to consider for autocompletion and
" facilitates identification of a delimiter's corresponding delimiter, e.g.,
" the key '{' yields '}' and vice versa.
let s:pairs = {
	\ "'": "'",
	\ '"': '"',
	\ '(': ')',
	\ '[': ']',
	\ '{': '}',
\ }
let s:opening_delims = keys(s:pairs)
let s:closing_delims = values(s:pairs)

" DRY: create the key-value pairs in the other direction.
call map(copy(s:pairs), 'extend(s:pairs, {v:val: v:key}, "keep")')

function s:autocomplete_delimiters(opening, closing)
	" s:autocomplete_delimiters() implementation {{{
	if mode() !=# 'i'
		return a:opening
	endif
	return a:opening .. a:closing .. "\<C-G>U\<Left>"
endfunction
"}}}

function s:autocomplete_quotes(quote)
	" s:autocomplete_quotes() implementation {{{
	let l:string = a:quote
	if mode() !=# 'i'
		return l:string
	endif
	let l:csr_line = getline('.')
	let l:csr_idx = col('.') - 1
	let l:c_bidx = klen#genlib#cursor_char_byte(v:false, '\S')
	let l:char = l:csr_line[l:c_bidx]    " char can be empty.
	let l:csr_quotes = klen#str#byteidx_quote_positions(
				\ l:csr_line[:l:c_bidx], l:csr_idx)
	if l:char ==# a:quote
	 \ && l:c_bidx == l:csr_quotes[1]
		let l:string = repeat("\<Del>", l:c_bidx - l:csr_idx)
			     \ .. "\<Right>"
	elseif (l:c_bidx == l:csr_quotes[0] || l:csr_quotes == [-1, -1])
	     \ && klen#genlib#cursor_char(v:true) =~ '\W\|^$'
		let l:string = s:autocomplete_delimiters(a:quote, a:quote)
	endif
	return l:string
endfunction
"}}}

function s:autodelim_brace()
	" s:autodelim_brace() implementation {{{
	let l:string = "{"
	if mode() !=# 'i'
		return l:string
	endif
	let l:string = s:autocomplete_delimiters('{', '}')
	let l:csr_line = getline('.')
	if l:csr_line =~ '\v^\s*$'
		let l:n = klen#str#match_chars(l:csr_line, '\s', col('.') - 1,
					     \ strlen(l:csr_line))
		let l:string = repeat("\<Del>", l:n) .. l:string
						   \ .. "\<CR>}\<BS>\<C-O>O"
	elseif l:csr_line =~ '\v^\s*%(struct|class|enum)%(\s+|$)'
		let l:string ..= "\<C-G>U\<Right>;"
			       \ .. repeat("\<C-G>U\<Left>", 2)
	endif
	return l:string
endfunction
"}}}

function s:autodelim_eat(delchar)
	" s:autodelim_eat() implementation {{{
	let l:string = a:delchar
	if mode() !=# 'i'
		return l:string
	endif
	let l:opening_indices = [] " Byte indices of open delims before cursor.
	let l:csr_pos = getcurpos()
	let l:c_pos = searchpos('\S', 'cW') " First char might be at cursor.
	call setpos('.', l:csr_pos)
	let l:char = getline(l:c_pos[0])[l:c_pos[1] - 1]
	let l:executed = v:false   " Checks if main loop iterated once.
	" Last cursor position when searching for an open delimiter.
	let l:last_open_pos = l:csr_pos[1:2]

	" Loop invariants:
	"  o  Cursor is at csr_pos.
	"  o  opening_indices includes indices of all valid opening delimiters
	"     within [last_open_pos[1] - 1, l:csr_pos[2] - 1).
	while index(s:closing_delims, l:char) >= 0
	    \ && (a:delchar != "\<BS>" || !l:executed)
		let l:quote_indices = klen#str#byteidx_quote_positions(
					\ getline('.'), l:c_pos[1] - 1)
		if l:char ==# "'" || l:char ==# '"'
			if l:c_pos[0] == line('.')
			 \ && l:c_pos[1] - 1 == l:quote_indices[1]
				call klen#genlib#push(l:opening_indices,
						    \ l:quote_indices[0])
				let l:last_open_pos[1] = l:quote_indices[0] + 1
			else
				break
			endif
		else
			call cursor(l:last_open_pos)
			let l:opening_pos = searchpairpos('\V'
					  \ .. s:pairs[l:char], '', '\V'
					  \ .. l:char, 'bW', '', line('.'))
			let l:opening_quotes
				\ = klen#str#byteidx_quote_positions(
				  \ getline('.'), l:opening_pos[1] - 1)
			if l:quote_indices == [-1, -1]
				while l:opening_pos != [0, 0]
				    \ && l:opening_quotes != l:quote_indices
					let l:opening_pos = searchpairpos('\V'
					      \ .. s:pairs[l:char], '', '\V'
					      \ .. l:char, 'bW', '', line('.'))
					let l:opening_quotes
					  \ = klen#str#byteidx_quote_positions(
					  \ getline('.'), l:opening_pos[1] - 1)
				endwhile
			endif
			if l:opening_pos[0] == line('.')
			 \ && l:opening_quotes == l:quote_indices
				call klen#genlib#push(l:opening_indices,
						    \ l:opening_pos[1] - 1)
				let l:last_open_pos[1] = l:opening_pos[1]
			else
				break
			endif
		endif
		call cursor(l:c_pos)
		let l:c_pos = searchpos('\S', 'W')
		call setpos('.', l:csr_pos)
		let l:char = getline(l:c_pos[0])[l:c_pos[1] - 1]
		let l:executed = v:true
	endwhile
	if !empty(l:opening_indices) " opening_indices is in descending order.
		let l:string ..= "\<Cmd>call " .. expand('<SID>')
		       \ .. "delete_closing([" .. join(l:opening_indices, ", ")
		       \ .. "])\<CR>"
	endif
	return l:string
endfunction
"}}}

function s:autodelim_enter()
	" s:autodelim_enter() implementation {{{
	let l:string = "\<CR>"
	if mode() !=# 'i'
		return l:string
	endif
	let l:next = klen#genlib#cursor_char(v:false, '\S')
	let l:prev = klen#genlib#cursor_char(v:true, '\S')
	if l:prev ==# '{' && l:next ==# '}'
		let l:bidx = klen#genlib#cursor_char_byte(v:true, '\S')
		let l:n = klen#str#match_chars(getline('.'), '\s', l:bidx + 1,
					     \ col('.') - 1)
		let l:string = repeat("\<BS>", l:n) .. "\<CR>}\<BS>\<C-O>O"
	endif
	return l:string
endfunction
"}}}

function s:autodelim_tab()
	" s:autodelim_tab() implementation {{{
	let l:string = "\<Tab>"
	if mode() !=# 'i'
		return l:string
	endif
	let l:csr_line = getline('.')
	let l:c_bidx = klen#genlib#cursor_char_byte(v:false, '\S')
	if index(s:closing_delims, l:csr_line[l:c_bidx]) >= 0
	 \ && s:matched(l:c_bidx)[0] == line('.')
		let l:string = repeat("\<Right>",
				    \ l:c_bidx - (col('.') - 1) + 1)
	endif
	return l:string
endfunction
"}}}

function s:matched(index, lnum = line('.'))
	" s:matched() implementation {{{
	let l:pos = [0, 0]
	let l:delim = getline(a:lnum)[a:index]
	if index(keys(s:pairs), l:delim) == -1
		return l:pos
	endif
	let l:quote_indices = klen#str#byteidx_quote_positions(getline(a:lnum),
							     \ a:index)
	if l:quote_indices != [-1, -1]
	 \ && klen#str#char_escaped(getline(a:lnum), a:index)
		return l:pos
	endif
	let l:csr_pos = getcurpos()
	if l:delim ==# "'" || l:delim ==# '"' || l:quote_indices != [-1, -1]
		let l:bidx = s:str_matched(getline(a:lnum), a:index)
		if l:bidx >= 0
			let l:pos = [a:lnum, l:bidx + 1]
		endif
	else
		if index(s:closing_delims, l:delim) >= 0
			let l:dir = 'b'
			let l:stop = line('w0') " Restrict search time.
			let l:d = #{open: s:pairs[l:delim], close: l:delim}
		else
			let l:dir = ''
			let l:stop = line('w$')
			let l:d = #{open: l:delim, close: s:pairs[l:delim]}
		endif
		call cursor(a:lnum, a:index + 1)
		let l:pos = searchpairpos('\V' .. d.open, '', '\V' .. d.close,
					\ dir .. 'W',
			\ 'klen#str#byteidx_quote_positions(getline("."),'
			\ .. 'col(".") - 1) != [-1, -1]', l:stop)
	endif
	call setpos('.', l:csr_pos)
	return l:pos
endfunction
"}}}

function s:skip_closing(closing)
	" s:skip_closing() implementation {{{
	let l:string = a:closing
	if mode() !=# 'i' || index(s:closing_delims, a:closing) == -1
		return l:string
	endif
	let l:csr_line = getline('.')
	let l:closing_pos = searchpairpos('\V' .. s:pairs[a:closing],
					\ '', '\V' .. a:closing, 'cnW')
	if l:closing_pos == [0, 0]
	 \ || s:matched(l:closing_pos[1] - 1, l:closing_pos[0]) == [0, 0]
		return l:string
	endif
	let l:n_chars = klen#str#match_chars(getline('.', l:closing_pos[0]),
				\ '\s', col('.') - 1, l:closing_pos[1] - 1)
	if l:n_chars >= 0
		let l:string = repeat("\<Del>", l:n_chars) .. "\<Right>"
	endif
	return l:string
endfunction
"}}}

" Helper functions
function s:delete_closing(indices)
	" For each byte index in indices, deletes up to and including the first
	" non-whitespace character after the cursor (crossing multiple lines if
	" necessary) so long as the byte index is at or exceeds the cursor's
	" byte index. For example, where @ indicates the cursor and indices
	" is [0, 1], the following text
	"			  1
	" Byte index:	012345678901234
	"		  @)          )$
	" becomes
	" Byte index:	012
	"		  @$
	" s:delete_closing() implementation {{{
	let l:csr_pos = getcurpos()
	" Manually handle the first iteration: a closing delimiter might be at
	" the cursor.
	let l:pos = (get(a:indices, 0, -1) >= l:csr_pos[2] - 1)
		  \ ? searchpos('\S', 'cW') : [0, 0]
	for l:bidx in a:indices[1:]
		if l:bidx < l:csr_pos[2] - 1
			break
		endif
		let l:tmp = searchpos('\S', 'W')
		if l:tmp == [0, 0]
			break
		endif
		let l:pos = l:tmp
	endfor
	if l:pos != [0, 0]
		call setpos('.', l:csr_pos)
		let l:n = klen#str#match_chars(getline('.', l:pos[0]), '.',
					     \ col('.') - 1, l:pos[1] - 1)
		execute "normal! i" .. repeat("\<Del>", l:n + 1)
		call setpos('.', l:csr_pos)
	endif
endfunction
"}}}

" Ensures: returns the byte index of the unescaped delimiter matching that
"	   found at {index} in {string} if both delimiters reside in or, for
"	   quotes, delimit the same string (see autodelim.txt for the
"	   definition of a string). If no such delimiter is found, the
"	   delimiter to consider is not a valid, unescaped delimiter or within
"	   a string, or {index} is out of range, returns -1.
function s:str_matched(string, index)
	" s:str_matched() implementation {{{
	let l:bidx = -1
	let l:delim = a:string[a:index]
	if index(keys(s:pairs), l:delim) == -1
		return l:bidx
	endif
	let l:quote_indices = klen#str#byteidx_quote_positions(a:string,
							     \ a:index)
	if l:quote_indices == [-1, -1]
	 \ || klen#str#char_escaped(a:string, a:index)
		return l:bidx
	endif

	if l:delim ==# "'" || l:delim ==# '"'
		if l:quote_indices[0] == a:index
			let l:bidx = l:quote_indices[1]
		elseif l:quote_indices[1] == a:index
			let l:bidx = l:quote_indices[0]
		endif
	else
		let l:end = (l:quote_indices[1] == -1)
			  \ ? strlen(a:string) : l:quote_indices[1]
		let l:range = (index(s:closing_delims, l:delim) >= 0)
			    \ ? range(a:index - 1, quote_indices[0] + 1, -1)
			    \ : range(a:index + 1, l:end - 1)
		let l:stack = [a:index]
		for i in l:range
			if a:string[i] ==# s:pairs[l:delim]
			 \ && !klen#str#char_escaped(a:string, i)
				if klen#genlib#peek(l:stack) == a:index
					let l:bidx = i
					break
				else
					call klen#genlib#pop(l:stack)
				endif
			elseif a:string[i] ==# l:delim
			     \ && !klen#str#char_escaped(a:string, i)
				call klen#genlib#push(l:stack, i)
			endif
		endfor
	endif
	return l:bidx
endfunction
"}}}

inoremap <expr> <special> (     <SID>autocomplete_delimiters('(', ')')
inoremap <expr> <special> [     <SID>autocomplete_delimiters('[', ']')
inoremap <expr> <special> {     <SID>autodelim_brace()
inoremap <expr> <special> )     <SID>skip_closing(')')
inoremap <expr> <special> ]     <SID>skip_closing(']')
inoremap <expr> <special> }     <SID>skip_closing('}')
inoremap <expr> <special> '     <SID>autocomplete_quotes("'")
inoremap <expr> <special> "     <SID>autocomplete_quotes('"')
inoremap <expr> <special> <BS>  <SID>autodelim_eat("\<BS>")
inoremap <expr> <special> <C-H> <SID>autodelim_eat("\<BS>")
inoremap <expr> <special> <C-U> <SID>autodelim_eat("\<C-G>u\<C-U>")
inoremap <expr> <special> <C-W> <SID>autodelim_eat("\<C-W>")
inoremap <expr> <special> <CR>  <SID>autodelim_enter()
inoremap <expr> <special> <Tab> <SID>autodelim_tab()
