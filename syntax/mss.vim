" Vim syntax file
" Language: Garmin Connect IQ Monkey Style Sheet

if exists("b:current_syntax")
  finish
endif

syntax case match

syntax keyword mssTodo FIXME NOTE TODO XXX contained
syntax region mssComment start="/\*" end="\*/" contains=mssTodo,@Spell
syntax match mssComment "//.*$" contains=mssTodo,@Spell
syntax match mssSelector "^\s*[^{}:;#/]\+\ze\s*{"
syntax match mssProperty "\<[-A-Za-z_][-A-Za-z0-9_]*\ze\s*:"
syntax match mssColor "#[0-9A-Fa-f]\{3,8}\>"
syntax match mssNumber "\<\d\+\(\.\d\+\)\?\(dp\|px\)\?\>"
syntax match mssNumber "\<\d\+\(\.\d\+\)\?%"
syntax match mssOperator "[{}:;,]"
syntax region mssString start=+"+ skip=+\\\\\|\\"+ end=+"+

highlight default link mssColor Constant
highlight default link mssComment Comment
highlight default link mssNumber Number
highlight default link mssOperator Operator
highlight default link mssProperty Identifier
highlight default link mssSelector Type
highlight default link mssString String
highlight default link mssTodo Todo

let b:current_syntax = "mss"
