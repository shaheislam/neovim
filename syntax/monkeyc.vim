" Vim syntax file
" Language: Monkey C (Garmin Connect IQ)

if exists("b:current_syntax")
  finish
endif

syntax case match

syntax keyword monkeycDeclaration as class const enum extends function hidden import module native new public static using var
syntax keyword monkeycStatement break continue return
syntax keyword monkeycConditional else if
syntax keyword monkeycRepeat do for while
syntax keyword monkeycException catch throw try
syntax keyword monkeycOperatorKeyword has instanceof
syntax keyword monkeycBoolean false true
syntax keyword monkeycNull null
syntax keyword monkeycTodo FIXME NOTE TODO XXX contained

syntax match monkeycNumber "\v<0[xX][0-9a-fA-F_]+>"
syntax match monkeycNumber "\v<\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d[\d_]*)?>"

syntax match monkeycOperator "=>\|==\|!=\|<=\|>=\|&&\|||\|[+*/%<>=!?:.-]"

syntax region monkeycString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=monkeycEscape
syntax match monkeycEscape "\\[\\\"nrtbf]" contained

syntax region monkeycComment start="/\*" end="\*/" contains=monkeycTodo,@Spell
syntax match monkeycComment "//.*$" contains=monkeycTodo,@Spell

syntax region monkeycAnnotation start="(:" end=")" contains=monkeycAnnotationName,monkeycString,monkeycNumber
syntax match monkeycAnnotationName ":\s*\h\w*" contained

syntax match monkeycModule "\<\u\w*\ze\."

highlight default link monkeycAnnotation PreProc
highlight default link monkeycAnnotationName PreProc
highlight default link monkeycBoolean Boolean
highlight default link monkeycComment Comment
highlight default link monkeycConditional Conditional
highlight default link monkeycDeclaration Keyword
highlight default link monkeycEscape SpecialChar
highlight default link monkeycException Exception
highlight default link monkeycModule Type
highlight default link monkeycNull Constant
highlight default link monkeycNumber Number
highlight default link monkeycOperator Operator
highlight default link monkeycOperatorKeyword Operator
highlight default link monkeycRepeat Repeat
highlight default link monkeycStatement Statement
highlight default link monkeycString String
highlight default link monkeycTodo Todo

let b:current_syntax = "monkeyc"
