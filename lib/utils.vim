vim9script

# Library of general functions.
# Documentation supplied in klen_lib.txt.
#
# 2021 Oct 25 - Written by Kenny Lam.

export def Peek(stack: list<any>): any
	# Peek() implementation {{{
	return stack[-1]
enddef
# }}}

export def Push(stack: list<any>, item: any)
	# Push() implementation {{{
	add(stack, item)
enddef
# }}}

export def Pop(stack: list<any>)
	# Pop() implementation {{{
	remove(stack, -1)
enddef
# }}}

export def Cursor_char(prev = false, pat = ''): string
	# Cursor_char() implementation {{{
	const csr_line = getline('.')
	const csr_idx = charcol('.') - 1
	var csr_char = ''
	if prev
		for i in range(csr_idx - 1, 0, -1)
			const char = csr_line[i]
			if char =~ pat
				csr_char = char
				break
			endif
		endfor
	else
		for char in csr_line[csr_idx :]->split('\zs')
			if char =~ pat
				csr_char = char
				break
			endif
		endfor
	endif
	return csr_char
enddef
# }}}

export def Cursor_char_byte(prev = false, pat = ''): number
	# Cursor_char_byte() implementation {{{
	const csr_line = getline('.')
	const csr_idx = charcol('.') - 1
	var c_bidx = -1
	if prev
		for i in range(csr_idx - 1, 0, -1)
			const char = csr_line[i]
			if char =~ pat
				c_bidx = i
				break
			endif
		endfor
	else
		for i in range(csr_idx, csr_line->strcharlen() - 1)
			const char = csr_line[i]
			if char =~ pat
				c_bidx = i
				break
			endif
		endfor
	endif
	return csr_line->byteidx(c_bidx)
enddef
# }}}
