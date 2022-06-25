vim9script noclear
import autoload 'klen/genlib.vim'
import autoload 'klen/str.vim'

const Peek = genlib.Peek
const Pop = genlib.Pop
const Push = genlib.Push

# Vim global plugin for automatically completing bracket delimiters.
# 2021 Oct 21 - Written by Kenny Lam.
# Last change:	2022 Jun 24

if exists("g:loaded_autodeli")
      finish
endif
g:loaded_autodeli = 1

# Line number of the blank line created from a multi-line brace autocompletion.
# It helps decide whether to delete the blank line automatically when leaving
# Insert mode.
var multiline_brace_blank_lnum = 0


# Autocommands {{{
augroup autodeli
	autocmd!
	autocmd InsertLeave * Brace_delete_line()
	autocmd BufWinEnter * Autodeli_track_buf()
	autocmd BufDelete * Autodeli_drop_buf()
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
	const csr_quotes = str.Bidx_quote_positions(csrline[: cbidx],
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
		      .. "\<ScriptCmd>Brace_multiline_post()\<CR>"
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
		const quote_indices = str.Bidx_quote_positions(getline('.'),
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
			var opening_quotes = str.Bidx_quote_positions(
					     getline('.'), opening_pos[1] - 1)
			if quote_indices == [-1, -1]
				while opening_pos != [0, 0]
				      && opening_quotes != quote_indices
					opening_pos = searchpairpos('\V'
						.. PAIRS[char], '', '\V'
						.. char, 'bW', '', line('.'))
					opening_quotes =
					      str.Bidx_quote_positions(
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
		if delchar =~ "\<C-U>"
			rhs ..= "\<ScriptCmd>Autodeli_eat_post_ctrl_u(["
				.. join(opening_indices, ", ") .. "], '"
				.. getline('.')[: csrpos[2] - 1]
				   ->substitute("'", "''", "g") .. "')\<CR>"
		else
			rhs ..= "\<ScriptCmd>Delete_closing(["
				.. join(opening_indices, ", ") .. "])\<CR>"
		endif
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
		      .. "\<ScriptCmd>Brace_multiline_post()\<CR>"
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

	if c_is_quote && str.Bidx_quote_positions(csrline, cbidx)[1] == cbidx
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

# Expects: {preline} is the string before the cursor prior to Insert-mode
#	   CTRL-U being applied.
# Ensures: like Delete_closing(), but specially handles Insert-mode CTRL-U: the
#	   byte indices of {indices} are adjusted relative to the cursor's
#	   expected, pre-auto-indented position before being passed to
#	   Delete_closing().
def Autodeli_eat_post_ctrl_u(indices: list<number>, preline: string)
	# Autodeli_eat_post_ctrl_u() implementation {{{
	final newidcs = deepcopy(indices)
	const precol = preline->len()	# Cursor assumed at end of preline
	const csrcol = col('.')
	# Normalized column data: values are relative to the first non-blank
	# characters in the respective strings.
	const nrmlprecol = precol - matchstr(preline, '\v^\s+')->len()
	const nrmlcsrcol = csrcol - matchstr(getline('.'), '\v^\s+')->len()

	if nrmlprecol < 1 || nrmlcsrcol < 1
		# The cursor line began with no non-blank characters before the
		# cursor or all of such characters were deleted by CTRL-U.
		newidcs->map('0x7fffffff')
		if nrmlcsrcol < 1
			normal ^
		endif
	else
		# Number of characters deleted.
		const n_del = nrmlprecol - nrmlcsrcol
		# Difference between where the cursor should be (no automatic
		# indentation) and the cursor's actual position:
		#	positive  =>  actual pos right of expected pos
		#	negative  =>  actual pos left of expected pos
		const offset = csrcol - (precol - n_del)

		if offset != 0
			newidcs->map((_, val) => val + offset)
		endif
	endif

	Delete_closing(newidcs)
enddef
# }}}

def Brace_delete_line()
	# Brace_delete_line() implementation {{{
	if getcurpos()[1] == multiline_brace_blank_lnum
	   && getline('.') =~ '\v^\s*$'
		delete _
	endif
	multiline_brace_blank_lnum = 0
enddef
# }}}

# Expects: a multi-line brace autocompletion occurred immediately before this
#	   function is called.
# Ensures: sets multiline_brace_blank_lnum to indicate a multi-line brace
#	   autocompletion occurred.
def Brace_multiline_post()
	# Brace_multiline_post() implementation {{{
	multiline_brace_blank_lnum = getcurpos()[1]
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
			execute 'imap <buffer>' .. c .. ' ' .. plug_name
		endif
	endfor
enddef
# }}}

def Define_plug_mappings()
	# Define_plug_mappings() implementation {{{
	# Vim9 expression mappings can access items local to the script in
	# which they were defined. This behavior means <SID> is unneeded here
	# for referring to script-local items; however, if these mappings are
	# defined elsewhere, e.g., in an editing session script (generated via
	# ":mksession"), the mappings will not be defined in this script and
	# thus cannot access the relevant script-local items. (Errors such as
	# "E117: Unknown function" will be issued.) Therefore, <SID> is still
	# used to avoid such a problem and suppress polluting the global
	# namespace.
	execute 'inoremap <expr> ' .. PLUG_NAMES['('] .. ' '
		.. expand('<SID>') .. 'Autocomplete_delimiters("(", ")")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['['] .. ' '
		.. expand('<SID>') .. 'Autocomplete_delimiters("[", "]")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['{'] .. ' '
		.. expand('<SID>') .. 'Autodeli_brace()'
	for close in CLOSING_DELIMS
		execute 'inoremap <expr> ' .. PLUG_NAMES[close] .. ' '
		    .. expand('<SID>') .. 'Skip_closing("' .. close .. '")'
	endfor
	execute 'inoremap <expr> ' .. PLUG_NAMES["'"] .. ' '
		.. expand('<SID>') .. 'Autocomplete_quotes("''")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['"'] .. ' '
		.. expand('<SID>') .. 'Autocomplete_quotes("\"")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<BS>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_eat("\<BS>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-H>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_eat("\<BS>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-U>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_eat("\<C-G>u\<C-U>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<C-W>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_eat("\<C-W>")'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<CR>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_enter()'
	execute 'inoremap <expr> ' .. PLUG_NAMES['<Tab>'] .. ' '
		.. expand('<SID>') .. 'Autodeli_tab()'
enddef
# }}}

# Expects: none
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

	const quote_indices = str.Bidx_quote_positions(argstr, idx)
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

def Remove_default_mappings()
	# Remove_default_mappings() implementation {{{
	for [lhs, plug_name] in PLUG_NAMES->items()
		if maparg(lhs, 'i') == plug_name
			execute 'iunmap <buffer>' lhs
		endif
	endfor
enddef
# }}}


# Autocommand functions {{{
# Expects: <abuf> is set by the autocommand event "BufDelete".
# Ensures: removes the buffer being deleted from PLUG_ON.
def Autodeli_drop_buf()
	# Autodeli_drop_buf() implementation {{{
	const btbd = expand("<abuf>")->str2nr()	# Buffer to be deleted.
	if PLUG_ON->has_key(btbd)
		PLUG_ON->remove(btbd)
	endif
enddef
# }}}

# Expects: none
# Ensures: adds the current buffer to PLUG_ON and applies Autodeli to it if
#	   Autodeli was enabled in the previous buffer (i.e., the alternate
#	   file).
def Autodeli_track_buf()
	# Autodeli_track_buf() implementation {{{
	const curbuf = bufnr()
	if PLUG_ON->has_key(curbuf)
		return
	endif
	const prevbuf = bufnr("#")
	PLUG_ON[curbuf] = (PLUG_ON->has_key(prevbuf)) ? PLUG_ON[prevbuf]
						      : false
	if PLUG_ON[curbuf]
		Autodeli on
	else
		Autodeli off
	endif
enddef
# }}}
# }}}


# Commands {{{
# Dictionary relating the valid arguments for the command "Autodeli" with their
# descriptions.
const ARGS_DESC = {
	'all': 'Defines the default Autodeli mappings for all buffers.',
	'help': 'Prints this "help" table.',
	'none': 'Removes the default Autodeli mappings for all buffers.',
	'off': 'Removes the default Autodeli mappings for the current buffer.',
	'on': 'Defines the default Autodeli mappings for the current buffer.',
}

# Dictionary relating the valid arguments for the command "Autodeli" with the
# commands that implement their behaviors. These commands use legacy script
# syntax and are executed at runtime via ":execute".
const ARGS_CMD = {
	'on': "call Define_default_mappings()",
	'off': "call Remove_default_mappings()",
	'all': "bufdo Define_default_mappings()",
	'none': "bufdo Remove_default_mappings()",
}

# A dictionary of formatted strings that compose a table associating the valid
# arguments for "Autodeli" and their descriptions.
final HELP_TABLE = {
	header: "",	# The table's header.
	fields: [],	# A List of Lists: each sublist represents a record,
			# and the items of such a sublist represent the fields
			# in that row.
}

# Dictionary associating buffer numbers with the state of the buffer-local
# Autodeli (on or off).
final PLUG_ON = {}

# Interface function that allows the user to query the state of Autodeli in an
# expression.
# Expects: none
# Ensures: returns true if Autodeli is enabled for buffer number {bufn}. By
#	   default, {bufn} is the current buffer's number. If {bufn} is not
#	   tracked by Autodeli, returns false.
def g:Autodeli_on(bufn = bufnr()): bool
	# Autodeli_on implementation {{{
	return (PLUG_ON->has_key(bufn)) ? PLUG_ON[bufn] : false
enddef
# }}}

# Expects: none
# Ensures: initializes the items of HELP_TABLE. This function need only be
#	   called once.
def Generate_help_table()
	# Generate_help_table() implementation {{{
	const titles = ["Command", "Description"] # Column titles.
	HELP_TABLE.header = titles[0]
	for i in range(1, titles->len() - 1)
		HELP_TABLE.header ..= "\t" .. titles[i]
	endfor
	# Character width of the fields under Column 0 (i.e., the leftmost text
	# column).
	const c0w = max([ARGS_DESC->mapnew((k, v) => k->len())->max(),
			titles[0]->len()])
	for [cmd, desc] in ARGS_DESC->items()->sort()
		HELP_TABLE.fields->add([])
		HELP_TABLE.fields[-1] += [cmd .. repeat(' ', c0w - cmd->len()),
					  desc]
	endfor
enddef
# }}}

Generate_help_table()

# Expects: none
# Ensures: executes the command given to the command "Autodeli".
def Autodeli_evaluate(arg: string)
	# Autodeli_evaluate() implementation {{{
	const argv = arg->split()
	if argv->empty()
		# Echo whether Autodeli is on for the current buffer {{{
		echo (PLUG_ON[bufnr()]) ? "  autodeli" : "noautodeli"
		# }}}
	elseif argv[0] == "help"
		# Print help table {{{
		const indent = repeat(' ', 4)	# Initial table indent.
		echohl Title
		echo indent .. HELP_TABLE.header
		echohl None
		for r in HELP_TABLE.fields
			echohl Identifier
			echo indent .. r[0] .. "\t"
			echohl None
			echon r[1]
		endfor
		# }}}
	elseif ARGS_CMD->has_key(argv[0])
		# Execute argument {{{
	try
		execute ARGS_CMD[argv[0]]
		if argv[0] == "on" || argv[0] == "all"
			PLUG_ON[bufnr()] = true
		elseif argv[0] == "off" || argv[0] == "none"
			PLUG_ON[bufnr()] = false
		endif
	catch /^Vim(bufdo):E37:/	# No write since last change.
		echohl ErrorMsg
		echo "Autodeli:" argv[0]
			.. ": Some buffers have unsaved changes."
		echohl None
	endtry
		# }}}
	else
		echohl ErrorMsg
		echo "Autodeli: unrecognized command:" argv[0]
		echohl None
	endif
enddef
# }}}

# Command to interact with this plugin, Autodeli.
command! -nargs=? Autodeli {
	Autodeli_evaluate(<q-args>)
}
# }}}


Define_plug_mappings()
if exists("g:startup_autodeli")
	Autodeli on
endif
