" Vim syntax file
" Language: Garmin Connect IQ Jungle

if exists("b:current_syntax")
  finish
endif

syntax case match

syntax keyword jungleTodo FIXME NOTE TODO XXX contained
syntax match jungleComment "#.*$" contains=jungleTodo,@Spell
syntax match jungleKey "^\s*[-A-Za-z0-9_.]\+\ze\s*="
syntax match jungleOperator "="
syntax match jungleVariable "\${[^}]\+}"
syntax region jungleString start=+"+ skip=+\\\\\|\\"+ end=+"+

highlight default link jungleComment Comment
highlight default link jungleKey Identifier
highlight default link jungleOperator Operator
highlight default link jungleString String
highlight default link jungleTodo Todo
highlight default link jungleVariable Special

let b:current_syntax = "jungle"
