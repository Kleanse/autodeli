vim9script
import autoload 'klen/genlib.vim'

const Peek = genlib.Peek
const Pop = genlib.Pop
const Push = genlib.Push

# Library of string functions.
# Documentation supplied in klen_lib.txt.
#
# 2021 Oct 25 - Written by Kenny Lam.

export def Byteidx_quote_positions(str: string, idx: number): list<number>
	# Byteidx_quote_positions() implementation {{{

	# Strings delimited by single quotes and strings delimited by double
	# quotes do not overlap, so they can be merged and sorted correctly.
	#     Index 0 is a List of matched indices, index 1 unmatched indices.
	final indices = str->Find_quotes('', true, true)
	const unmatched_bidx = indices[1]->get(0, -1)

	# Case 1: char at {idx} is delimiter of a string.
	var listidx = indices[0]->index(idx)
	if listidx >= 0
		return (listidx->and(1))
			? [indices[0][listidx - 1], indices[0][listidx]]
			: [indices[0][listidx], indices[0][listidx + 1]]
	endif

	# Case 2: {idx} is in an unterminated string.
	if 0 <= unmatched_bidx && unmatched_bidx <= idx
		return [unmatched_bidx, -1]
	endif

	# Case 3: {idx} is within a string.
	sort(indices[0], 'f')
	for i in range(indices[0]->len())
		if indices[0][i] > idx
			if i->and(1)
				return [indices[0][i - 1], indices[0][i]]
			else
				break
			endif
		endif
	endfor
	return [-1, -1]
enddef
# }}}

export def Char_escaped(str: string, idx: number, char = '\'): bool
	# Char_escaped() implementation {{{
	var n_chars = 0
	for i in range(str->charidx(idx) - 1, 0, -1)
		if str[i] == char
			++n_chars
		else
			break
		endif
	endfor
	return n_chars->and(1) == 1
enddef
# }}}

export def Get_delimiters(str: string, delims: list<string>,
			  unmatched = false): list<list<number>>
	# Get_delimiters() implementation {{{
	final matched_indices = [[], []]
	final unmatched_indices = [[], []]
	var next_open_idx  = str->stridx(delims[0])
	var next_close_idx = str->stridx(delims[1])
	while next_open_idx != -1 || next_close_idx != -1
		if next_open_idx == -1
			next_open_idx = 0x7fffffff
		elseif next_close_idx == -1
			next_close_idx = 0x7fffffff
		endif

		var startidx = 0
		if next_open_idx < next_close_idx
			unmatched_indices[0]->Push(next_open_idx)
			startidx = next_open_idx + 1
		else
			if !unmatched_indices[0]->empty()
				matched_indices[0]->Push(
						unmatched_indices[0]->Peek())
				matched_indices[1]->Push(next_close_idx)
				unmatched_indices[0]->Pop()
			else
				unmatched_indices[1]->Push(next_close_idx)
			endif
			startidx = next_close_idx + 1
		endif
		next_open_idx  = str->stridx(delims[0], startidx)
		next_close_idx = str->stridx(delims[1], startidx)
	endwhile
	return (unmatched) ? matched_indices + unmatched_indices
			   : matched_indices
enddef
# }}}

export def Get_same_delimiters(str: string, delim: string,
			       unmatched = false): list<any>
	# Get_same_delimiters() implementation {{{
	if delim == '"' || delim == "'"
		return str->Find_quotes(delim, unmatched)
	endif
	final matched_indices = []
	final unmatched_indices = []
	var bidx = 0	# Byte index of current character.
	for c in str->split('\zs')
		if c == delim
			if unmatched_indices->empty()
				unmatched_indices->Push(bidx)
			else
				matched_indices->Push(
						unmatched_indices->Peek())
				matched_indices->Push(bidx)
				unmatched_indices->Pop()
			endif
		endif
		bidx += strlen(c)
	endfor
	return (unmatched) ? [matched_indices, unmatched_indices]
			   : matched_indices
enddef
# }}}

export def In_string(str: string, idx: number): bool
	# In_string() implementation {{{
	return Byteidx_quote_positions(str, idx) != [-1, -1]
enddef
# }}}

export def Match_chars(expr: any, pat: string, start: any, end: any): number
	# Match_chars() implementation {{{
	final realexpr = (type(expr) == v:t_string) ? [expr] : expr
	final realstart = (type(start) == v:t_number) ? [0, start] : start
	final realend = (type(end) == v:t_number)
			? [len(realexpr) - 1, end] : end

	if realend[0] < realstart[0] || realstart[0] == realend[0]
	   && realend[1] < realstart[1]
		# end is on a line before start or if both are on the same
		# line, end is some byte before start.
		return -1
	endif

	var n_chars = 0
	if realstart[0] == realend[0]
		# Use slice() so that realend[1] == 0 does not fetch the entire
		# string (via expr-[:]).
		for c in realexpr[realstart[0]]
				->slice(realstart[1], realend[1])->split('\zs')
			if c !~ pat
				return -1
			endif
			n_chars += (&delcombine) ? 1 : strchars(c)
		endfor
		return n_chars
	endif

	for c in realexpr[realstart[0]][realstart[1] :]->split('\zs')
		if c !~ pat
			return -1
		endif
		n_chars += (&delcombine) ? 1 : strchars(c)
	endfor
	# Account for new line.
	++n_chars

	for s in realexpr[realstart[0] + 1 : realend[0] - 1]
		for c in s->split('\zs')
			if c !~ pat
				return -1
			endif
			n_chars += (&delcombine) ? 1 : strchars(c)
		endfor
		++n_chars
	endfor
	for c in realexpr[realend[0]]->slice(0, realend[1])->split('\zs')
		if c !~ pat
			return -1
		endif
		n_chars += (&delcombine) ? 1 : strchars(c)
	endfor
	return n_chars
enddef
# }}}

# Local functions
def Find_quotes(str: string, quote: string,
		unmatched = false, both = false): list<any>
	# If {both} is true, returns a List containing the byte indices of both
	# single quotes and double quotes; {quote} is ignored in this case.
	#
	# A string is defined to be a sequence of characters delimited by
	# either single quotes or double quotes, where the opening quote
	# succeeds the start of line or a non-word character. Strings cannot be
	# nested, and they cannot span across multiple lines. Instances of the
	# quote delimiting a string can be used within the same string so long
	# as they are escaped with backslashes. Quotes within a string
	# delimited by the alternative quotes have no special meaning,
	# regardless of whether they are escaped.
	#
	# Find_quotes() implementation {{{
	final matched_indices = []
	final unmatched_indices = []
	final state = {
		in_str: false,	# True if inside a string.
		quote: '',	# Quote type of the surrounding string.
		n_backs: 0,	# Number of sequential backslashes before
				#   current character.
		pc_is_wc: false	# True if previous character is a word
				#   character.
	}
	const qt_pat = (both) ? '''\|"' : quote
	var bidx = 0	# Byte index of current character.
	for c in str->split('\zs')
		# Track a valid instance of argument quote.
		if c =~ qt_pat
			if !state.in_str && !state.pc_is_wc
			   || state.in_str && state.quote == c
			      && !state.n_backs->and(1)
				if unmatched_indices->empty()
					unmatched_indices->Push(bidx)
				else
					matched_indices->Push(
						unmatched_indices->Peek())
					matched_indices->Push(bidx)
					unmatched_indices->Pop()
				endif
			endif
		endif
		# Update state.
		if c == "'" || c == '"'
			if !state.in_str && !state.pc_is_wc
				state.in_str = true
				state.quote = c
			elseif state.in_str && state.quote == c
			       && !state.n_backs->and(1)
				state.in_str = false
			endif
		endif
		if c == '\'
			++state.n_backs
		else
			state.n_backs = 0
		endif
		state.pc_is_wc = c =~ '\w'
		bidx += strlen(c)
	endfor
	return (unmatched) ? [matched_indices, unmatched_indices]
			   : matched_indices
enddef
# }}}
