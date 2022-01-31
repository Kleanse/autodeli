vim9script noclear
import autoload 'klen/genlib.vim'
import autoload 'klen/str.vim'

const Peek = genlib.Peek
const Pop = genlib.Pop
const Push = genlib.Push

# Vim global plugin for automatically completing bracket delimiters.
# 2021 Oct 21 - Written by Kenny Lam.

if exists("g:loaded_autodeli")
      finish
endif
g:loaded_autodeli = 1

# Dirty hack (why is this variable not a Boolean?) used for the multi-line
# outcomes of brace autocompletion. The value 1 indicates the current Insert
# mode experienced a multi-line brace autocompletion; leaving Insert mode in
# this case will delete the cursor line if it is blank.
var autocompleted_multiline_brace = 2

# Autocommands {{{
augroup autodeli
	autocmd!
	autocmd InsertLeave * Brace_delete_line()
augroup END
# }}}

# Dictionary that contains the delimiters to consider for autocompletion and
# facilitates identification of a delimiter's corresponding delimiter, e.g.,
# the key '{' yields '}' and vice versa.
final PAIRS = {
	"'": "'",
	'"': '"',
	'(': ')',
	'[': ']',
	'{': '}',
}
const CLOSING_DELIMS = PAIRS->values()

# Create the key-value pairs in the other direction.
for [key, val] in copy(PAIRS)->items()
	PAIRS->extend({[val]: key}, 'keep')
endfor

# Dictionary associating characters to plugin mapping names, which follow the
# format
#	<Plug>autodeli_<name>;
final PLUG_NAMES = {
	'<BS>': '<Plug>autodeli_backspace;',
	'<C-H>': '<Plug>autodeli_ctrl-h;',
	'<C-U>': '<Plug>autodeli_ctrl-u;',
	'<C-W>': '<Plug>autodeli_ctrl-w;',
	'<CR>': '<Plug>autodeli_enter;',
	'<Tab>': '<Plug>autodeli_tab;',
}

for delim in keys(PAIRS)
	PLUG_NAMES[delim] = '<Plug>autodeli_' .. delim .. ';'
endfor

# Like <Left> and <Right>, but do not break undo sequence.
const LEFT  = "\<C-G>U\<Left>"
const RIGHT = "\<C-G>U\<Right>"

def Autocomplete_delimiters(opening: string, closing: string): string
	# Autocomplete_delimiters() implementation {{{
	if mode() != 'i'
		return opening
	endif
	return opening .. closing .. LEFT
enddef
# }}}

def Autocomplete_quotes(quote: string): string
	# Autocomplete_quotes() implementation {{{
	var rhs = quote
	if mode() != 'i'
		return rhs
	endif

	const csrline = getline('.')
	const csridx = col('.') - 1
	const cbidx = genlib.Cursor_char_byte(false, '\S')
	const c = (cbidx == -1) ? '' : csrline[cbidx]
	const csr_quotes = str.Byteidx_quote_positions(csrline[: cbidx],
						       csridx)
	const csr_in_string = csr_quotes != [-1, -1]

	if c == quote && cbidx == csr_quotes[1]
		rhs = repeat("\<Del>", cbidx - csridx) .. RIGHT
	elseif (csridx == csr_quotes[0] || !csr_in_string)
			&& genlib.Cursor_char(true) =~ '\W\|^$'
		rhs = Autocomplete_delimiters(quote, quote)
	endif
	return rhs
enddef
# }}}

def Autodeli_brace(): string
	# Autodeli_brace() implementation {{{
	var rhs = "{"
	if mode() != 'i'
		return rhs
	endif

	rhs = Autocomplete_delimiters('{', '}')
	const csrline = getline('.')
	if csrline =~ '\v^\s*$'
		const n = str.Match_chars(csrline, '\s', col('.') - 1,
					  csrline->len())
		rhs = repeat("\<Del>", n) .. rhs .. "\<CR>}\<BS>\<C-O>O"
		autocompleted_multiline_brace = 0
	elseif csrline =~ '\v^\s*%(struct|class|enum)%(\s+|$)'
		rhs ..= RIGHT .. ";" .. repeat(LEFT, 2)
	endif
	return rhs
enddef
# }}}

def Autodeli_eat(delchar: string): string
	# Autodeli_eat() implementation {{{
	var rhs = delchar
	if mode() != 'i'
		return rhs
	endif

	final opening_indices = [] # Byte indices of open delims before cursor.
	const csrpos = getcurpos()
	var cpos = searchpos('\S', 'cW') # First char might be at cursor.
	setpos('.', csrpos)
	var char = getline(cpos[0])[cpos[1] - 1]
	var executed = false	# Checks if main loop iterated once.
	# Last cursor position when searching for an open delimiter.
	final last_open_pos = csrpos[1 : 2]

	# Loop invariants:
	#  o  Cursor is at its original position.
	#  o  opening_indices includes indices of all valid opening delimiters
	#     within [last_open_pos[1] - 1, csrpos[2] - 1).
	while CLOSING_DELIMS->index(char) >= 0
	      && (delchar != "\<BS>" || !executed)
		const quote_indices = str.Byteidx_quote_positions(getline('.'),
								  cpos[1] - 1)
		if char == "'" || char == '"'
			if cpos[0] == line('.')
			   && cpos[1] - 1 == quote_indices[1]
				opening_indices->Push(quote_indices[0])
				last_open_pos[1] = quote_indices[0] + 1
			else
				break
			endif
		else
			cursor(last_open_pos)
			var opening_pos = searchpairpos('\V' .. PAIRS[char],
					'', '\V' .. char, 'bW', '', line('.'))
			var opening_quotes = str.Byteidx_quote_positions(
					     getline('.'), opening_pos[1] - 1)
			if quote_indices == [-1, -1]
				while opening_pos != [0, 0]
				      && opening_quotes != quote_indices
					opening_pos = searchpairpos('\V'
						.. PAIRS[char], '', '\V'
						.. char, 'bW', '', line('.'))
					opening_quotes =
					      str.Byteidx_quote_positions(
					      getline('.'), opening_pos[1] - 1)
				endwhile
			endif
			if opening_pos[0] == line('.')
			   && opening_quotes == quote_indices
				opening_indices->Push(opening_pos[1] - 1)
				last_open_pos[1] = opening_pos[1]
			else
				break
			endif
		endif

		cursor(cpos)
		cpos = searchpos('\S', 'W')
		var cstr = getline(cpos[0])
		if cstr[cpos[1] - 1] == ';' && cstr[cpos[1] - 2] == '}'
			# Skip the semicolon following a closing brace.
			cpos = searchpos('\S', 'W')
			cstr = getline(cpos[0])
		endif
		setpos('.', csrpos)
		char = cstr[cpos[1] - 1]
		executed = true
	endwhile

	if !empty(opening_indices) # opening_indices is in descending order.
		rhs ..= "\<ScriptCmd>Delete_closing(["
			.. join(opening_indices, ", ") .. "])\<CR>"
	endif
	return rhs
enddef
# }}}

def Autodeli_enter(): string
	# Autodeli_enter() implementation {{{
	var rhs = "\<CR>"
	if mode() != 'i'
		return rhs
	endif

	const nextc = genlib.Cursor_char(false, '\S')
	const prevc = genlib.Cursor_char(true, '\S')

	if prevc == '{' && nextc == '}'
		const prevc_bidx = genlib.Cursor_char_byte(true, '\S')
		const n = str.Match_chars(getline('.'), '\s', prevc_bidx + 1,
					  col('.') - 1)
		rhs = repeat("\<BS>", n) .. "\<CR>}\<BS>\<C-O>O"
		autocompleted_multiline_brace = 0
	endif
	return rhs
enddef
# }}}

def Autodeli_tab(): string
	# Autodeli_tab() implementation {{{
	var rhs = "\<Tab>"
	if mode() != 'i'
		return rhs
	endif

	const csrline = getline('.')
	const cbidx = genlib.Cursor_char_byte(false, '\S')
	if cbidx == -1
		return rhs
	endif
	const c = csrline[cbidx]
	const c_is_quote = c == "'" || c == '"'

	if c_is_quote
	      && str.Byteidx_quote_positions(csrline, cbidx)[1] == cbidx
	   || !c_is_quote && CLOSING_DELIMS->index(c) >= 0
	      && Matched(cbidx)[0] == line('.')
		rhs = repeat(RIGHT, cbidx - (col('.') - 1) + 1)
	endif
	return rhs
enddef
# }}}

def Matched(idx: number, lnum = line('.')): list<number>
	# Matched() implementation {{{
	var pos = [0, 0]
	const delim = getline(lnum)[idx]
	if PAIRS->keys()->index(delim) == -1
		return pos
	endif

	const in_string = str.In_string(getline(lnum), idx)
	if in_string && str.Char_escaped(getline(lnum), idx)
		return pos
	endif

	const save_csrpos = getcurpos()
	if delim == "'" || delim == '"' || in_string
		const bidx = Str_matched(getline(lnum), idx)
		if bidx >= 0
			pos = [lnum, bidx + 1]
		endif
	else
		var dir = ''		# Search direction
		var stop = line('w$')	# Line at which to stop the search
		var d = {open: delim, close: PAIRS[delim]} # Delimiter data
		if CLOSING_DELIMS->index(delim) >= 0
			dir = 'b'
			stop = line('w0')
			d = {open: PAIRS[delim], close: delim}
		endif
		cursor(lnum, idx + 1)
		pos = searchpairpos('\V' .. d.open, '', '\V' .. d.close,
				    dir .. 'W',
			'str.In_string(getline("."), col(".") - 1)', stop)
	endif
	setpos('.', save_csrpos)
	return pos
enddef
# }}}

def Skip_closing(closing: string): string
	# Skip_closing() implementation {{{
	var rhs = closing
	if mode() != 'i' || CLOSING_DELIMS->index(closing) == -1
		return rhs
	endif

	const closing_pos = searchpairpos('\V' .. PAIRS[closing], '',
					  '\V' .. closing, 'cnW')
	if closing_pos == [0, 0]
	   || Matched(closing_pos[1] - 1, closing_pos[0]) == [0, 0]
		return rhs
	endif

	const n_chars = str.Match_chars(getline('.', closing_pos[0]), '\s',
					col('.') - 1, closing_pos[1] - 1)
	if n_chars >= 0
		rhs = repeat("\<Del>", n_chars) .. RIGHT
	endif
	return rhs
enddef
# }}}

# Helper functions
def Brace_delete_line()
	# Brace_delete_line() implementation {{{
	if autocompleted_multiline_brace == 1 && getline('.') =~ '\v^\s*$'
		delete _
	endif
	++autocompleted_multiline_brace
enddef
# }}}

def Delete_closing(indices: list<number>)
	# For each byte index in indices, deletes up to and including the first
	# non-whitespace character after the cursor (crossing multiple lines if
	# necessary) so long as the byte index is at or exceeds the cursor's
	# byte index. For example, where @ indicates the cursor and {indices}
	# is [2, 3], the following text
	#			  1
	# Byte index:	012345678901234
	#		  @)          )
	# becomes
	# Byte index:	012
	#		  @
	# If such a non-whitespace character is a closing brace and a semicolon
	# immediately succeeds it, deletes the semicolon as well: given the
	# indices [0, 1], the text
	# Byte index:	0123
	#		@};}
	# becomes
	# Byte index:	0
	#		@
	# Delete_closing() implementation {{{
	const csrpos = getcurpos()
	var end = [0, 0]
	for bidx in indices
		if bidx < csrpos[2] - 1
			break
		endif
		final tmp = searchpos('\S', 'cW')
		if tmp == [0, 0]
			break
		else
			const s = getline(tmp[0])
			if s[tmp[1] - 1] == '}' && s[tmp[1]] == ';'
				++tmp[1]
			endif
		endif
		cursor(tmp[0], tmp[1] + 1)
		end = tmp
	endfor

	if end != [0, 0]
		setpos('.', csrpos)
		const n = str.Match_chars(getline('.', end[0]), '.',
					  csrpos[2] - 1, end[1] - 1)
		execute "normal! i" .. repeat("\<Del>", n + 1)
		setpos('.', csrpos)
	endif
enddef
# }}}

def Define_default_mappings()
	# Define_default_mappings() implementation {{{
	for [c, plug_name] in PLUG_NAMES->items()
		if !hasmapto(plug_name, 'i')
			execute 'imap ' .. c .. ' ' .. plug_name
		endif
	endfor
enddef
# }}}

def Define_plug_mappings()
	# Define_plug_mappings() implementation {{{
	execute 'inoremap <expr> ' .. PLUG_NAMES['('] .. ' '
		.. 'Autocomplete_delimiters("(", ")")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['['] .. ' '
		.. 'Autocomplete_delimiters("[", "]")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['{'] .. ' '
		.. 'Autodeli_brace()'
	for close in CLOSING_DELIMS
		execute 'inoremap <expr> ' .. PLUG_NAMES[close] .. ' '
		    .. 'Skip_closing("' .. close .. '")'
	endfor
	execute 'inoremap <expr> ' .. PLUG_NAMES["'"] .. ' '
		.. 'Autocomplete_quotes("''")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['"'] .. ' '
		.. 'Autocomplete_quotes("\"")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<BS>'] .. ' '
		.. 'Autodeli_eat("\<BS>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-H>'] .. ' '
		.. 'Autodeli_eat("\<BS>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-U>'] .. ' '
		.. 'Autodeli_eat("\<C-G>u\<C-U>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-W>'] .. ' '
		.. 'Autodeli_eat("\<C-W>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<CR>'] .. ' '
		.. 'Autodeli_enter()'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<Tab>'] .. ' '
		.. 'Autodeli_tab()'
enddef
# }}}

# Ensures: returns the byte index of the unescaped delimiter matching that
#	   found at {idx} in {argstr} if both delimiters reside in or, for
#	   quotes, delimit the same string (see autodeli.txt for the definition
#	   of a string). If no such delimiter is found, the delimiter to
#	   consider is not a valid, unescaped delimiter or within a string,
#	   returns -1.
def Str_matched(argstr: string, idx: number): number
	# Str_matched() implementation {{{
	var bidx = -1
	const delim = argstr[idx]
	if PAIRS->keys()->index(delim) == -1
		return bidx
	endif

	const quote_indices = str.Byteidx_quote_positions(argstr, idx)
	const idx_in_string = quote_indices != [-1, -1]
	if !idx_in_string || str.Char_escaped(argstr, idx)
		return bidx
	endif

	if delim == "'" || delim == '"'
		if quote_indices[0] == idx
			bidx = quote_indices[1]
		elseif quote_indices[1] == idx
			bidx = quote_indices[0]
		endif
	else
		const end = (quote_indices[1] == -1) ? argstr->len()
						     : quote_indices[1]
		const range = (CLOSING_DELIMS->index(delim) >= 0)
			       ? range(idx - 1, quote_indices[0] + 1, -1)
			       : range(idx + 1, end - 1)
		final stack = [idx]

		for i in range
			if argstr[i] == PAIRS[delim]
			   && !str.Char_escaped(argstr, i)
				if stack->Peek() == idx
					bidx = i
					break
				else
					stack->Pop()
				endif
			elseif argstr[i] == delim
					&& !str.Char_escaped(argstr, i)
				stack->Push(i)
			endif
		endfor
	endif
	return bidx
enddef
# }}}

Define_plug_mappings()
Define_default_mappings()
