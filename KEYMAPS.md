# Keymap Audit

Persistent audit of repo-configured executable mappings. The approved target layout below is canonical; concurrent source changes landed that layout during the audit. There are no old-key aliases.

## Conventions

- Audit date: 2026-09-17. Leader is `<Space>`; local leader is `\`.
- Modes: `n` normal, `x` visual, `s` select, `v` visual/select as written by the source, `o` operator-pending, `i` insert, `t` terminal.
- Scope: `global` survives across ordinary buffers; `lazy` is a global lazy.nvim loader map; `buffer` is attached only to the named buffer/filetype/UI; `native` is a plugin-owned mapping explicitly configured in this repo.
- Namespace policy: global/editor maps live in `lua/config/keymaps.lua`; plugin maps live with their plugin; LSP maps attach per buffer. Every executable leader prefix must have one semantic owner. Buffer-local UI maps may intentionally shadow global maps because the local owner is visible and bounded.
- Prefix guards: `<leader>a`, `<leader>ao`, `<leader>ap`, and `<leader>as` are explicit `n,x <Nop>` guards; normal mode also guards `<leader>q`, `<leader>v`, `<leader>t`, `<leader>T`, `<leader>x`, `<leader>H`, `<leader>R`, and `<leader>gL`. They prevent incomplete prefixes from falling through to native commands. Executable exact-prefix maps must not block descendants: quit moves off `<leader>q`, viewport moves off `<leader>w`, Diffview moves off `<leader>gL`, and Rust open-Cargo moves off `<leader>Rc`.
- Descriptions are the configured `desc`/plugin action labels, compacted only for punctuation/case. A semicolon separates distinct mappings; every key remains named.

## Namespace Layout

| Prefix | Owner/policy |
|---|---|
| `<leader>a` | AI: OpenCode `<leader>aa`, `<leader>ai`, `<leader>ax`, remaining OpenCode controls under `<leader>ao`; Pi `<leader>ap`; Sidekick `<leader>as`; Wrapped `<leader>aw`; annotations `<leader>an`. Guarded. |
| `<leader>b` | Buffers. Diffview may shadow `<leader>b` buffer-locally to toggle its file panel. |
| `<leader>c` | Code/data/navigation; includes LSP-adjacent Aerial and directory navigation. |
| `<leader>d` | DAP. |
| `<leader>f` | Find/FZF; `<leader>fd` is DAP discovery. |
| `<leader>g` | Git; `<leader>go` Octo, `<leader>gL` GitLab, `<leader>gi` Diffview line history. |
| `<leader>h` | Git hunks. |
| `<leader>H` | HTTP/Kulala target namespace. |
| `<leader>J` | Structured-data graph UI. |
| `<leader>k` | kubectl. |
| `<leader>l` | LSP/trace; `<leader>L` lint/security. |
| `<leader>m` | Markdown/messages. Markdown preview owns `<leader>mp`; Noice persistence owns `<leader>mP`. |
| `<leader>o` | Obsidian, including task queries `<leader>oP`/`<leader>oC`. |
| `<leader>O` | Reserved historical Octo group label; executable Octo maps are under `<leader>go`. |
| `<leader>q` | Quickfix/loclist prefix only. Quit is `<leader>Q`. |
| `<leader>R` | Rust and Cargo/crates only. Rust open-Cargo is `<leader>Ro`; `<leader>Rc…` is crates. |
| `<leader>s` | Symbols, sessions, and SSH currently share this non-blocking namespace. |
| `<leader>t` | Tests and Typr. |
| `<leader>T` | Typst. |
| `<leader>v` | Viewport modes. |
| `<leader>w` | Save/window root; only `<leader>w` is executable after viewport migration. |
| `<leader>x` | Cleanup: Mini trailspace. |
| `<leader>y` | Yank/permalink. |

Reserved top-level prefixes are `a b c d f g h H J k l L m n o O p q R s t T v w x y`. Repo-explicit free top-level letter prefixes are `i j r u z`; singleton `<leader>-`, `<leader>e`, `<leader>Q`, and `<leader><leader>` are occupied and are not free prefixes.

## Global And Lazy Maps

Target keys are shown for approved migrations.

| Owner | Modes/scope/load | Explicit mappings: action | Source |
|---|---|---|---|
| Core | `t global`, startup | `<Esc><Esc>`: exit terminal mode; `<C-Space>`: leave terminal and start leader | `lua/config/keymaps.lua` |
| Core windows | `n global`, startup | `<C-Up>`/`<C-Down>`: height +2/-2; `<C-Left>`/`<C-Right>`: width -2/+2 | `lua/config/keymaps.lua` |
| Core editing | `v global`, startup | `J`/`K`: move selected line down/up; `<`/`>`: indent and retain selection | `lua/config/keymaps.lua` |
| Core commands | `n global`, startup | `<Esc>`: clear search; `<leader>w`: save; `<leader>Q`: quit | `lua/config/keymaps.lua` |
| kubectl | `n global`, startup | `<leader>kf`: cp from pod; `<leader>kt`: cp to pod; `<leader>kp`: picker; `<leader>kl`: list pods | `lua/config/keymaps.lua` |
| Scroll | `n,v,x global`, startup | `<C-d>`: half-page up via `<C-u>`; `<C-f>`: half-page down via `<C-d>` | `lua/config/keymaps.lua` |
| Formatting | `n,x global`, startup | `gq`: Treesitter-aware format; `gw`: same, keep cursor | `lua/config/keymaps.lua` |
| Structured data | `n,x global`, startup | `<leader>cj`: jq whole buffer/selection; `<leader>cy`: yq whole buffer/selection | `lua/config/keymaps.lua` |
| Search/paste | `n/x global`, startup | `n`/`N`: centered next/previous result; `x <leader>p`: paste without yanking | `lua/config/keymaps.lua` |
| Yank | `v global`, startup | `<leader>yr`: selection with relative path; `<leader>ya`: selection with absolute path | `lua/config/keymaps.lua` |
| Permalinks | `n,v global`, startup | `<leader>yl`: Git forge permalink for line/selection; `<leader>yL`: Markdown permalink for line/selection | `lua/config/keymaps.lua` |
| Annotations | `global`, setup | `n,x <leader>ana`: add; `n <leader>anc`/`<leader>anC`: copy current/all; `<leader>ano`/`<leader>anO`: ask OpenCode current/all; `<leader>anl`: list; `<leader>and`/`<leader>anD`: delete current/all; `]a`/`[a`: next/previous | `lua/config/annotations.lua` |
| Prefix guards | `global`, eager which-key config | `n,x <leader>a`: AI; `<leader>ao`: advanced OpenCode; `<leader>ap`: Pi; `<leader>as`: NES. Normal-only `<leader>q`: quickfix; `<leader>v`: viewport; `<leader>t`: tests; `<leader>T`: Typst; `<leader>x`: trim; `<leader>H`: HTTP; `<leader>R`: Rust; `<leader>gL`: GitLab. All are `<Nop>`. | `lua/plugins/which-key.lua` |
| OpenCode | `lazy`; listed modes; `:Opencode`/key/startup flag | `n,t <leader>aoc`: toggle; `n,t <C-.>`: toggle; `n,x <leader>aa`: ask current context/selection; `x <leader>aoS`: append selection; `n <leader>aoB`/`aoV`/`aoQ`: ask buffer/visible/quickfix; `n,x <leader>ax`: actions; `x <leader>aoI`: transform selection; `n,x go`: range operator; `n goo`: line operator | `lua/plugins/opencode.lua` |
| OpenCode prompts | `lazy n,x` | `<leader>aoe`: explain; `<leader>aof`: fix; `<leader>aor`: review; `<leader>aot`: tests; `<leader>aod`: document; `<leader>aoo`: optimize; `<leader>ai`: implement; `<leader>aoE`: explain diagnostics | `lua/plugins/opencode.lua` |
| OpenCode session/search | `lazy n` | `<leader>aon`: new; `<leader>aop`: pick; `<leader>aom`: compact; `<leader>aou`/`aoU`: undo/redo; `<leader>aoA`: cycle agent; `<leader>ao/`: all messages; `<leader>aoP`: prompts; `<leader>aoL`: assistant; `<leader>aoT`: tools; `<leader>aoR`: reasoning; `<leader>aoO`: tool output; `<leader>aoG`: all local sessions; `<leader>aoF`: fork pane; `<leader>aoW`: fork worktree; `<leader>aog`: live grep | `lua/plugins/opencode.lua` |
| Pi | `lazy n/x`, Pi commands/keys | `n,x <leader>apa`: ask/ask selection; `n <leader>apc`: cancel; `<leader>apl`: log | `lua/plugins/pi.lua` |
| Sidekick | `lazy`, keys | `n,i <leader>asj`: jump/apply NES; `n <leader>asu`: update; `<leader>asd`: raw-response debug; `<leader>asx`: clear | `lua/plugins/sidekick.lua` |
| Wrapped | `lazy n`, key/`:WrappedNvim` | `<leader>aw`: dashboard | `lua/plugins/wrapped.lua` |
| Navigation | `lazy n,t`, eager plugin | `<C-h>`/`<C-j>`/`<C-k>`/`<C-l>`: left/down/up/right across Vim/tmux; `<C-\>`: previous | `lua/plugins/navigation.lua` |
| Viewport | `lazy n,t`, keys | `<C-z>`: maximize/restore; `n <leader>vv`: resize mode; `<leader>vn`: navigate mode; `<leader>vs`: select mode | `lua/plugins/viewport.lua` |
| Oil/Canola | `lazy n,v`, eager/key | `<leader>e`: browser (`n,v`); `n <leader>fe`: browser; `n -`: parent directory | `lua/plugins/oil.lua` |
| Yazi | `lazy n`, VeryLazy | `<leader>-`: at file; `<leader>cw`: cwd; `<leader>cr`: resume | `lua/plugins/yazi.lua` |
| ToggleTerm | `lazy n`, key | `<leader>ft`: project terminal split | `lua/plugins/toggleterm.lua` |
| FZF files/text | `lazy`, keys | `n <leader>ff`/`fF`: files/local home; `<leader>fb`/`fB`: buffers/all; `<leader>fr`/`fR`: recent local/global; `<leader>fg`/`fG`: grep/all excluding tests; `<leader>fw`/`fW`: word/WORD; `v <leader>fv`: selection | `lua/plugins/fzf-lua.lua` |
| FZF misc | `lazy n`, keys | `<leader>fa`: AWS accounts; `<leader>fu`: changes; `<leader>fm`: marks; `<leader>fh`: help; `<leader>fc`: commands; `<leader>f<leader>`: resume; `<leader>fq`: quickfix; `<leader>fz`: builtin menu; `<leader>fp`: projects; `<leader>fy`: yank history; `<leader>cd`: zoxide/Oil | `lua/plugins/fzf-lua.lua` |
| FZF DAP | `lazy n`, project.nvim spec keys | `<leader>fdb`: breakpoints; `<leader>fdc`: commands; `<leader>fdC`: configurations; `<leader>fdv`: variables; `<leader>fdf`: frames | `lua/plugins/fzf-lua.lua` |
| FZF Git | `lazy n`, keys | `<leader>gg`: status; `<leader>gl`: commits; `<leader>gb`: branches; `<leader>gf`: files; `<leader>gC`: buffer commits; `<leader>gs`: stash; `<leader>gx`: conflict markers; `<leader>gD`: cross-picker Diffview refs | `lua/plugins/fzf-lua.lua` |
| Fugitive | `lazy n`, key/commands | `<leader>gp`: push; `<leader>gc`: commit; `<leader>gB`: browser | `lua/plugins/git/fugitive.lua` |
| Flog | `lazy n/v`, key/commands | `<leader>gG`: graph; `<leader>gV`: graph split; `n <leader>gY`: current-file graph; `<leader>gW`: current-file graph split; `v <leader>gY`: selected-lines graph | `lua/plugins/git/flog.lua` |
| Git workflow | `global`, Diffview plugin setup | `n,v <leader>gK`: compare clipboard with buffer/selection; `]r`/`[r`: next/previous file commit; `]R`/`[R`: next/previous repo commit; `gco`/`gcO`: checkout TO/FROM commit | `lua/git/workflow.lua` |
| Diffview launchers | `lazy n/v`, keys | `<leader>gd`: toggle; `<leader>gh`/`gH`: file/repo history; `<leader>gm`: conflicts; `n,v <leader>gi`: line/range history; `<leader>gP`: PR preview; `<leader>gS`: staged; `<leader>gT`: stash history; `<leader>gR`: retarget revs; `<leader>gr`: reviewed files; `<leader>gX`: clear reviewed; `<leader>gE`: directories; `<leader>gF`: files | `lua/plugins/git/diffview.lua` |
| GitLab | `lazy n`, keys | `<leader>gLc`: choose MR; `gLS`: start review; `gLs`: summary; `gLd`: discussions; `gLp`: pipeline; `gLA`: approve; `gLR`: revoke; `gLM`: merge; `gLm`: auto-merge; `gLC`: create MR; `gLn`: note; `gLP`: publish drafts; `gLD`: draft mode; `gLo`: browser; `gLu`: copy URL | `lua/plugins/git/gitlab.lua` |
| Octo | `lazy n`, `:Octo`/ft/keys | `<leader>gon`: notifications; `<leader>gop`: PR/issues hub; `<leader>gok`: checks; `<leader>gor`/`goR`/`gos`: start/resume/submit review; `<leader>goA`: actions; `<leader>gob`: repo browser; `<leader>goy`: repo URL; `<leader>god`: PR in Diffview | `lua/plugins/octo.lua` |
| Gitsigns | `buffer n/v/x/o`, `BufReadPre`/`BufNewFile` attach | `]c`/`[c`: next/previous hunk; `[C`/`]C`: first/last; `]p`/`[p`: next/previous with preview; `]g`/`[g`: non-contiguous; `]s`/`[s`: staged; `]u`/`[u`: unstaged | `lua/plugins/git/gitsigns.lua` |
| Gitsigns actions | `buffer`, attach | `n,s,x <leader>hs`: stage hunk/select/visual lines; `n,s,x <leader>hr`: reset; `<leader>hS`: stage buffer; `<leader>hu`: undo stage; `<leader>hP`: preview+stage; `<leader>hR`: reset buffer; `<leader>hp`: preview; `<leader>hi`: inline preview; `<leader>hb`: full blame line; `<leader>hB`: toggle line blame; `<leader>hv`: blame buffer; `<leader>hO`: blame commit in Diffview; `<leader>hd`/`hD`: diff/index or `~`; `<leader>hc`: custom revision; `<leader>ht`: deleted; `<leader>hy`: yank deleted; `<leader>hC`/`hE`: change/reset base; `<leader>hF`: reset to revision; `<leader>hn`/`hl`/`hw`/`hg`: numhl/linehl/word diff/signs; `<leader>hq`/`hQ`/`hL`: quickfix all/all buffers/location; `<leader>hx`/`hX`: select contiguous/current hunk; `o,x ih`/`ah`: inside/around hunk | `lua/plugins/git/gitsigns.lua` |
| Lint | `global n`, `BufReadPre`/`BufNewFile` | `<leader>Ll`: linters; `<leader>Lk`: kube-linter; `<leader>LT`: Trivy directory; `<leader>LP`: Conftest file | `lua/plugins/lint.lua` |
| DAP | `lazy n`, key | `<leader>td`: debug nearest test; `<leader>db`/`dB`: breakpoint/conditional; `<leader>dc`/`dC`: continue/run to cursor; `<leader>dt`: terminate; `<leader>di`/`do`/`dO`: into/over/out; `<leader>dr`: REPL; `<leader>dl`: last; `<leader>dh`/`dp`: hover/preview | `lua/plugins/dap.lua` |
| Neotest | `lazy n`, key | `<leader>tt`: file; `<leader>tT`: all; `<leader>tr`: nearest; `<leader>tl`: last; `<leader>ts`: summary; `<leader>to`: output; `<leader>tO`: output panel; `<leader>tS`: stop; `<leader>tw`: watch | `lua/plugins/neotest.lua` |
| Typr | `lazy n`, commands/keys | `<leader>ty`: game; `<leader>tY`: stats | `lua/plugins/typr.lua` |
| Mini cleanup | `lazy n`, eager plugin | `<leader>xw`: trim trailing whitespace; `<leader>xl`: trim last empty lines | `lua/plugins/mini.lua` |
| Typst | `lazy n`, `typst` ft | `<leader>Tw`: watch/preview; `<leader>Tc`: compile; `<leader>To`: open PDF | `lua/plugins/typst.lua` |
| Kulala | `lazy n`, `http`/`rest` ft | `<leader>Hs`: send; `<leader>Ht`: headers/body; `<leader>Hn`/`Hp`: next/previous; `<leader>Hi`: inspect; `<leader>He`: environment; `<leader>Hc`: copy cURL; `<leader>Hr`: replay; `<leader>Ha`: all; `<leader>HS`: scratchpad; `<leader>Hq`: close; `<leader>HG`: GraphQL schema | `lua/plugins/kulala.lua` |
| Markdown | `lazy n`, markdown ft/commands | `<leader>mp`: browser preview; `<leader>mr`: refresh review markers; `<leader>mq`: markers to quickfix; `<leader>mt`: toggle in-buffer rendering; `<leader>mi`: clear images when image.nvim is enabled | `lua/plugins/markdown.lua`, `render-markdown.lua`, `image.lua` |
| Noice | `lazy`, VeryLazy | `n,i,v <C-c>`: dismiss; `n <leader>mh`: history; `<leader>ml`: last; `<leader>md`: dismiss; `<leader>n`: notification history; `<leader>mP`: persistent messages | `lua/plugins/noice.lua` |
| Obsidian | `lazy n/v`, vault events/keys | `<leader>od`/`oy`/`om`: today/yesterday/tomorrow; `<leader>oo`: switch; `<leader>os`: search; `<leader>ob`: backlinks; `<leader>ol`: outgoing; `<leader>ok`: tags; `<leader>or`/`oR`/`oF`: semantic related/query/folder; `<leader>oS`: suggest backlinks; `<leader>oH`: history; `<leader>on`: new; `<leader>ot`: template; `<leader>oc`: checkbox; `<leader>oP`/`oC`: pending/completed tasks; `<leader>op`: paste image; `v <leader>oL`/`oN`: link/new link | `lua/plugins/obsidian.lua`, `img-clip.lua` |
| Rust | `buffer n`, rustacean LSP attach | `<leader>Ra`: action; `<leader>Rd`: debuggables; `<leader>Rr`: runnables; `<leader>RT`: testables; `K`: hover actions; `<leader>Re`: expand macro; `<leader>Ro`: open Cargo; `<leader>Rp`: parent module; `<leader>Rj`: join; `<leader>Rs`: SSR; `<leader>Rg`: crate graph | `lua/plugins/lsp-rust.lua` |
| Crates | `buffer n/v`, Cargo.toml LSP attach | `n,v <leader>Rc`: `<Nop>` crates prefix guard; `n <leader>RV`/`RF`: versions/features; `<leader>Rcd`: dependencies; `<leader>Rcu`: update crate; `v <leader>Rcs`: update selected; `n <leader>Rca`: update all; `<leader>RcU`: upgrade crate; `v <leader>RcS`: upgrade selected; `n <leader>RcA`: upgrade all; `<leader>Rch`/`Rcr`/`RcD`/`RcC`/`RcL`: homepage/repo/docs/crates.io/lib.rs | `lua/plugins/lsp-rust.lua` |
| Aerial | `lazy n`, LspAttach | `<leader>cs`: symbols; `<leader>cS`: nav | `lua/plugins/aerial.lua` |
| Trace | `lazy n`, key/commands | `<leader>lu`: trace up; `<leader>lU`: origin; `<leader>lz`: provenance tree; `<leader>lp`: peek | `lua/plugins/trace.lua` |
| Quickfix | `lazy n`, VeryLazy | `<leader>qq`: toggle quickfix; `<leader>ql`: loclist; `<Tab>`: jump to visible quickfix | `lua/plugins/quickfix.lua` |
| Session | `global n`, eager plugin | `<leader>so`: toggle project session; `<leader>sX`: delete | `lua/plugins/session.lua` |
| SSHFS | `lazy n`, commands/keys | `<leader>sc`: connect; `<leader>sf`: files; `<leader>sg`/`sG`: grep/live grep; `<leader>sF`: live find; `<leader>st`: terminal; `<leader>sd`/`sD`: disconnect one/all | `lua/plugins/sshfs.lua` |
| Videre | `lazy n`, command/key | `<leader>Jo`: graph explorer | `lua/plugins/videre.lua` |

## LSP, Filetype, And Buffer-Local Maps

| Owner/scope | Explicit mappings: action | Source/trigger |
|---|---|---|
| LSP-attached buffer | `]d`/`[d`: next/previous diagnostic; `]e`/`[e`: error; `]w`/`[w`: warning; `<leader>ld`/`lD`: buffer/workspace diagnostics; `<leader>lc`/`lC`: run/refresh codelens; `K`: hover; `n,i <leader>lh`: signature; `gd`/`gr`/`gI`/`gy`: definition/references/implementation/type; `n,v <leader>la`: action; `<leader>lr`: rename; `<leader>ss`/`sS`: document/workspace symbols; `<leader>li`/`lo`: incoming/outgoing list; `<leader>lI`/`lO`: incoming/outgoing tree; `<leader>lT`/`lt`: all/buffer LSP toggle; `<leader>ls`: status | `lua/plugins/lsp.lua`, `LspAttach` |
| UFO LSP buffer | `K`: fold preview, falling back to LSP hover | `lua/plugins/lsp-enhancements.lua`, `LspAttach` |
| Treesitter textobjects | `o,x af`/`if`: function outer/inner; `ac`/`ic`: class; `ab`/`ib`: block; `al`/`il`: loop; `aa`/`ia`: parameter; `is`: statement outer; `n,x,o ]f`/`[f`: function; `]c`/`[c`: class; `]b`/`[b`: block; `]l`/`[l`: loop | `lua/plugins/treesitter.lua`, BufReadPost/BufNewFile |
| Obsidian note buffer | `gf`/`<CR>`: smart follow/action; `gj`/`gk`: next/previous heading; `zk`/`zl`: fold to H2/H3; `zu`: disable folds; `<A-x>`: complete and move task | `lua/plugins/obsidian.lua`, `enter_note` |
| Markdown buffer | `i <Space>`: literal space, bypass blink.pairs parsing | `lua/plugins/blink-pairs.lua`, markdown FileType/existing buffers |
| Oil buffer | `<leader>ff`/`fg`: files/grep in Oil directory; `<C-y>l`/`s`/`g`: filename/git-relative/`~/work`-relative path. `<C-l>` and `<C-h>` are explicitly disabled so tmux navigation survives. | `lua/plugins/oil.lua`, native keymap config |
| Quickfix buffer | `>`/`<`: expand/collapse context; `r`: refresh; `q`: close; `<Tab>`: source window; `<CR>`: open; `j`/`k`: next/previous with preview | `lua/plugins/quickfix.lua`, quicker native/on_qf |
| Generic close filetypes | `q`: close in `qf`, `help`, `man`, `lspinfo`, `checkhealth` | `lua/config/autocmds.lua`, FileType |
| Fugitive buffer | `q`/`<Esc>`: close; `r`: refresh; `<CR>`: select/open | `lua/plugins/git/fugitive.lua`, fugitive FileType |
| Git commit buffer | `q`: cancel/close | `lua/plugins/git/fugitive.lua`, gitcommit FileType |
| Flog graph buffer | `n <CR>`: commit in Diffview; `v <CR>`: selected range in Diffview; `q`: close; `y`: hash; `gx`: browser | `lua/git/flog.lua`, floggraph FileType |
| Gitsigns blame buffer | `d`: Diffview commit; `q`: close. Plugin-native `s`, `S`, `e` are explicitly removed. | `lua/plugins/git/gitsigns.lua`, gitsigns-blame FileType |
| Clipboard diff scratch | `q`: close diff/tab | `lua/git/workflow.lua`, generated scratch buffers |
| Commit-info buffer | `<CR>`: checkout FROM/TO or show checkpoint; `q`: close Diffview | `lua/git/workflow.lua`, generated buffer |
| LSP hierarchy buffer | `<CR>`: jump; `o`: expand/collapse; `K`: full path; `q`/`<Esc>`: close | `lua/lsp-hierarchy.lua`, generated tree |
| Annotation panel | `q`/`<Esc>`: close; `<CR>`/`o`: open; `e`: edit; `d`: delete; `c`: copy; `a`/`A`: ask current/all; `?`: help | `lua/config/annotations.lua`, generated panel |
| Notification history | `q`/`<Esc>`: close | `lua/plugins/noice.lua`, generated buffer |
| Obsidian suggestion/history floats | `q`/`<Esc>`: close | `lua/plugins/obsidian.lua`, generated buffers |
| OpenCode prompt | `n <Esc>`/`q`: close; `i <C-Space>`: start leader; plus generated FZF prompt maps below | `lua/plugins/opencode.lua`, generated NUI input |
| OpenCode terminal | generated FZF prompt maps below in normal mode | `lua/plugins/opencode.lua`, terminal create/start |
| OpenCode message picker | `t <C-l>`: send literal Ctrl-L | `lua/config/opencode_pickers.lua`, picker creation |
| OpenCode transcript | `q`: close; `r`: refresh; `s`/`/`: search | `lua/config/opencode_pickers.lua`, generated transcript |
| OpenCode transform review | `gdc`: cancel; `y`: accept; `n`: reject. Installation fails closed if any key already has a buffer map. | `lua/config/opencode_transform.lua`, active transform only |
| FZF preview | `t <C-t>`: focus preview; preview-buffer `n <C-t>`: focus search; `<Esc>`/`q`: close picker; `i`: edit previewed file | `lua/plugins/fzf-lua.lua`, picker window creation |
| ToggleTerm buffer | `t <C-q>`: close; `<Esc><Esc>`: normal mode | `lua/plugins/toggleterm.lua`, TermOpen |
| Typr buffer | `n <Esc>`: close and clean floats | `lua/plugins/typr.lua`, native `on_attach` |

## Generated Prompt Maps

`config.fzf_prompt` generates these buffer-local maps in OpenCode terminal/prompt buffers. In current owners the prefix is unchanged, so all are normal-mode `<leader>` maps: `<leader>ff` files, `fF` home files, `fb` buffers, `fB` all buffers, `fr` recent, `fR` global recent, `fg` text, `fG` text excluding tests, `fw` word, `fW` WORD, `fu` changes, `fm` marks, `fh` help, `fc` commands, `fq` quickfix, `fp` projects, `fy` yanks, `<leader>cd` zoxide, `<leader>gg` status, `gl` commits, `gb` branches, `gf` files, `gC` buffer commits, `gs` stash, `gx` conflicts, `<leader>ld`/`lD` diagnostics, `<leader>ss`/`sS` symbols, `<leader>li` incoming calls, `<leader>fdb`/`fdv`/`fdf` DAP breakpoints/variables/frames, `<leader>fa` AWS accounts, and `<leader>fz` picker menu. Each inserts the selected value into the owning composer rather than performing the ordinary global action.

## Explicit Plugin-Native Maps

Only mappings whose keys/actions are explicitly present in this repo are listed. Enabled upstream defaults that are not enumerated locally are covered under limitations.

| Owner/scope | Explicit mappings: action | Source |
|---|---|---|
| Mini surround | `sa`: add (`n,x`); `sd`: delete; `sf`/`sF`: find right/left; `sh`: highlight; `sr`: replace; `sn`: update search lines | `lua/plugins/mini.lua` |
| Mini comment | `gc`: operator/visual toggle/textobject; `gcc`: line toggle | `lua/plugins/mini.lua` |
| Mini move | `n,x <M-h>`/`<M-l>`/`<M-j>`/`<M-k>`: move line/selection left/right/down/up | `lua/plugins/mini.lua` |
| Mini splitjoin | `gS`: toggle split/join | `lua/plugins/mini.lua` |
| Blink completion | `<Tab>`: accept completion, then Sidekick/native inline completion, then fallback; `<S-Tab>`: previous; `<C-Space>`: show/docs toggle; `<C-e>`: hide. Preset `default` is enabled but its unnamed defaults are not expanded here. | `lua/plugins/blink-cmp.lua` |
| Yazi | `<F1>` help; `<C-v>` vertical; `<C-x>` horizontal; `<C-t>` tab; `<C-s>` grep directory; `<C-g>` replace directory; `<Tab>` cycle buffers; `<C-y>` copy selected relative paths; `<C-q>` quickfix | `lua/plugins/yazi.lua` |
| Wrapped UI | `q`: close; `r`: refresh; `<`/`>`: previous/next year | `lua/plugins/wrapped.lua` |
| CodeCompanion review | review quickfix `n a`: accept; `c`: comment; `d`: diff baseline; `x`: ignore file | `lua/plugins/codecompanion.lua` |
| Neoclip FZF | `Enter`: select; `<C-p>`: paste; `<C-k>`: paste behind; `<C-y>`: copy selection | `lua/plugins/fzf-lua.lua` |
| nvim-bqf FZF | `<C-s>`: split; `<C-t>`: tab drop; `<C-o>`: toggle all | `lua/plugins/quickfix.lua` |
| FZF global | native fzf `<C-f>`/`<C-d>`: preview up/down; `<C-b>`: preview page up; `<C-/>`: toggle preview. Builtin preview `<C-/>` and legacy `<C-_>`: toggle preview. Global actions `<C-y>` copy location for files/buffers, command for commands/history, register for registers. | `lua/plugins/fzf-lua.lua` |
| FZF files | `Enter`: edit; `<C-g>`: Flog selected paths; `<M-g>`/`<M-s>`/`<M-l>`/`<M-d>`/`<M-p>`: global/git/local/buffer-dir/parent scope; `<M-b>`/`<M-n>`: scope history back/forward; `<M-o>`: directory browser; `<C-r>`: search history; `<C-y>`: path; `<C-f>`: absolute path | `lua/plugins/fzf-lua.lua` |
| FZF grep | `Enter`: edit; `<C-g>`: Flog paths; `<M-g>`/`<M-s>`/`<M-l>`/`<M-d>`/`<M-p>`: scopes; `<M-b>`/`<M-n>`: history; `<M-o>`: directories; `<M-q>`: quickfix scope; `<C-r>`: search history; `<M-i>`: ignore; `<C-h>`: hidden; `<C-y>`: location; `<C-f>`: absolute path | `lua/plugins/fzf-lua.lua` |
| FZF buffers | `Enter`: edit/quickfix; `<M-g>`/`<M-s>`/`<M-l>`/`<M-d>`: scopes; `<M-b>`/`<M-n>`: history; `<C-d>`: delete+resume; `<C-r>`: history; `<C-y>`: location; `<C-f>`: absolute path | `lua/plugins/fzf-lua.lua` |
| FZF oldfiles | `Enter`: edit; `<M-g>`/`<M-s>`/`<M-l>`/`<M-d>`/`<M-p>`: scopes; `<M-b>`/`<M-n>`: history; `<C-r>`: search history | `lua/plugins/fzf-lua.lua` |
| FZF directory browser | `Enter`: descend; `<C-x>`: choose directory; `<M-b>`/`<M-f>`: history back/forward; `<M-p>`: parent | `lua/plugins/fzf-lua.lua` |
| FZF history | `Enter`: relaunch query; `<C-d>`/`<C-s>`/`<C-g>`: local/service/global; `<C-e>`: remove local item; `<C-c>`: clear local; `<C-y>`: copy displayed query | `lua/plugins/fzf-lua.lua` |
| FZF Git | status `<C-y>` copy status; worktrees `<C-y>` copy; files `<C-r>` history, `<C-y>` path, `<C-f>` absolute; commits/buffer commits `Enter` checkout/edit, `<C-g>` Diffview, `<C-r>` history, `<C-y>` SHA; branches `Enter` switch, `<C-r>` history, `<C-y>` branch; stash `Enter` apply, `<C-x>` drop, `<C-r>` history, `<C-y>` stash | `lua/plugins/fzf-lua.lua` |
| FZF LSP | symbols/references/definitions/implementations/document/workspace symbols: `<C-y>` copy location, `<C-f>` copy absolute path | `lua/plugins/fzf-lua.lua` |
| FZF AWS/project/zoxide | AWS `Enter`/`<C-y>` account, `<M-y>` profile, `<M-b>` both; project `Enter` cd, `<C-y>` path; zoxide/parents `<M-g>`/`<M-s>`/`<M-l>`/`<M-p>` scopes, `Enter` cd+Oil, `<C-y>` path, zoxide `<Tab>` drill down | `lua/plugins/fzf-lua.lua` |
| FZF Diffview ref picker | `<C-h>` commits; `<C-b>` branches; `<C-s>` stashes; `<C-w>` worktrees; `<C-/>` preview; `<C-x>` clear; `<C-y>` copy current ref; `Enter` select/proceed. File filter: `Enter` selected files, `<C-a>` all, `<C-y>` path. | `lua/plugins/fzf-lua.lua` |
| Diffview view | `g0`: first change; `<Tab>`/`<S-Tab>`: next/previous file; `[F`/`]F`: first/last; `gf`/`<C-w><C-f>`/`<C-w>gf`: edit/split/tab; `g<C-x>`: layout; `<leader>e`/`<leader>b`: focus/toggle files; `q`: close; `co`/`ct`/`cb`/`ca`/`dx`: ours/theirs/base/all/delete conflict; `<leader>cO`/`cT`/`cB`/`cA`/`dX`: whole-file equivalents; `[x`/`]x`: conflicts; `[c`/`]c`: hunks | `lua/plugins/git/diffview.lua` |
| Diffview file panel | `j`/`<Down>` and `k`/`<Up>`: next/previous; `<CR>`/`o`/`l`/double-click: select; `-`/`s`: stage toggle; `S`/`U`: stage/unstage all; `R`: refresh; `L`: log; `g<C-x>`: layout; `<leader>e`/`b`: focus/toggle; `q`: close; `i`: listing; `f`: flatten; `gf`/`<C-w><C-f>`/`<C-w>gf`: edit/split/tab; `<leader>cO`/`cT`/`cB`/`cA`/`dX`: whole-file conflict actions | `lua/plugins/git/diffview.lua` |
| Diffview history/options | history `g!`: options; `<C-A-d>`: open in Diffview; `<CR>`/`o`/double-click: select; `y`: hash; `g<C-x>`: layout; `<leader>e`/`b`: focus/toggle; `q`: close. Option panel `<Tab>`: select; `q`: close. | `lua/plugins/git/diffview.lua` |
| Octo issue/PR buffers | issue: `<leader>goic` close, `goio` reopen, `goil` list. PR: `<leader>gopo` checkout, `gopm` merge, `gops` squash, `gopr` rebase, `gopc` commits, `gopf` files, `gopd` diff, `gova`/`govd` reviewer add/remove. Shared: `<C-r>` reload, `<C-b>` browser, `<C-y>` URL, `<leader>goaa`/`goad` assignee, `gola`/`gold` label, `gogi` goto, `goca`/`gocd` comment, `gorp`/`gorh`/`gore`/`gor+`/`gor-`/`gorr`/`gorl`/`gorc` reactions. | `lua/plugins/octo.lua` |
| Octo review UIs | thread: `<leader>gogi`, `goca`, `gosa`, `gocd`; `]c`/`[c` comments; `]q`/`[q`/`[Q`/`]Q` files; `<C-c>` close; reaction keys above. Submit: `<C-a>` approve, `<C-m>` comment, `<C-r>` changes, `<C-c>` close. Diff: `<leader>govs` submit, `govd` discard, `goca` comment, `gosa` suggestion, `goe` focus, `gof` toggle, `]t`/`[t` threads, file navigation keys, `<C-c>` close, `gotv` viewed, `gf` file. File panel: `j`/`k`, `<CR>`, `R`, review/focus/toggle/navigation/close/viewed keys above. | `lua/plugins/octo.lua` |
| Octo notifications | `<C-r>` read; `<C-d>` done; `<C-u>` unsubscribe; `<C-b>` browser; configured common action `<C-y>` copy URL; `<M-a>`/`<M-p>`/`<M-i>`/`<M-d>` type all/PR/issue/discussion; `<M-s>`/`<M-o>`/`<M-c>`/`<M-m>` state all/open/closed/merged; `<S-Up>`/`<S-Down>` preview page | `lua/plugins/octo.lua` |
| Octo checks | `Enter`: logs; `<C-b>` job page; `<C-y>` link; `<C-o>` all checks | `lua/plugins/octo.lua` |
| Octo hub | `Enter`: open; `<C-s>`/`<C-v>`: split/vsplit; `<C-b>` browser; `<C-o>` create; `<M-t>` entity; `<M-s>` state; `<M-u>` author; `<M-m>` scope; `<M-l>` label; `<M-g>` global; `<M-f>` search; `<M-r>` refresh; `<C-n>` comment; `<C-r>` thumbs-up; `<C-y>` URL; PR-only `<C-d>` Diffview, `<C-x>` checkout, `<M-k>` checks; `<S-Up>`/`<S-Down>` preview page | `lua/plugins/octo.lua` |

## Scoped Shadowing And Surviving Owners

- `<Esc>` global startup owner is superseded after Noice loads by Noice's combined clear-highlight+dismiss mapping. Generated prompts, FZF previews, notification buffers, Fugitive, and hierarchy buffers intentionally shadow it locally.
- `q` remains a common transient close key in quickfix, Diffview, Flog, Fugitive, generated scratch/panel/transcript/history buffers, and selected filetypes. These are buffer-local and intentionally shadow native recording only while that UI owns the buffer.
- `K` is buffer-local for LSP hover/UFO fold preview and Rust hover; hierarchy uses its own transient `K`. Rust and UFO both attach `K` in Rust LSP buffers, so the effective callback is the last runtime writer; this is a surviving scoped overlap, not a global namespace conflict.
- `<C-l>` is tmux navigation globally in terminal mode; OpenCode's picker buffer intentionally shadows it to pass literal Ctrl-L.
- `<leader>e` and `<leader>b` are global Oil/buffer namespaces, but Diffview intentionally shadows them within its panels/views for focus/toggle.
- `]c`/`[c` are Treesitter class navigation in ordinary parsed buffers, Gitsigns hunks in Git-attached buffers, native diff movement in diff windows, and Octo comments in review threads. Buffer-local context decides the surviving owner.
- `]q`/`[q`/`[Q`/`]Q` remain quickfix-style navigation in Octo review buffers. Diffview uses separate file keys except its configured panel mappings.
- After migration, surviving global owners are: OpenCode on `aa`/`ai`/`ax`; Markdown preview on `mp`; Noice on `mP`; Obsidian tasks on `oP`/`oC`; Neotest on `tt`/`tl`/`to`/`tw`; Mini cleanup on `xw`/`xl`; Typst on `Tw`/`Tc`/`To`; Kulala on `H*`; Rust on `R*` with open-Cargo `Ro` and crates `Rc*`; GitLab on `gL*`; Diffview line history on `gi`; quickfix on `q*`; quit on `Q`; save on `w`; viewport on `v*`.

## Pre-Change Conflicts And Approved Resolutions

These conflicts were present in the inspected source before migration. “Prefix” means an executable shorter map delayed or blocked longer descendants; “exact” means multiple global/lazy owners registered the same mode/key.

| Kind | Pre-change owners/key | Approved resolution |
|---|---|---|
| layout | OpenCode ask `<leader>aoa` retained unnecessary nested namespace | OpenCode ask `<leader>aa` |
| layout | OpenCode implement `<leader>aoi` and actions `<leader>aox` | `<leader>ai` and `<leader>ax` |
| exact | Noice persistence and Markdown preview both `<leader>mp` | Noice `<leader>mP`; Markdown survives on `<leader>mp` |
| exact | Obsidian pending `<leader>tt` vs Neotest file tests; Obsidian completed `<leader>tc` vs Typst compile | Obsidian `<leader>oP`/`<leader>oC`; Neotest `<leader>tt` and Typst `<leader>Tc` survive |
| exact | Mini trim `<leader>tw`/`tl` vs Neotest watch/last; `tw` also Typst watch | Mini `<leader>xw`/`xl`; Neotest `<leader>tw`/`tl` survive |
| exact | Typst `<leader>tw`/`tc`/`to` vs Mini/Neotest/Obsidian | Typst `<leader>Tw`/`Tc`/`To`; Neotest retains lowercase test namespace |
| exact | Kulala `<leader>Rs`/`Rp`/`Re`/`Rc`/`Rr`/`Ra` vs Rust | All Kulala `<leader>R*` become same-suffix `<leader>H*`; Rust survives on `<leader>R*` |
| prefix | Rust open Cargo `<leader>Rc` vs crates `<leader>Rcd`, `Rcu`, `Rcs`, `Rca`, `RcU`, `RcS`, `RcA`, `Rch`, `Rcr`, `RcD`, `RcC`, `RcL` | Rust open Cargo `<leader>Ro`; crates retain `<leader>Rc*` |
| prefix | Diffview line history `<leader>gL` vs GitLab `<leader>gL*` | Diffview `<leader>gi`; GitLab retains `<leader>gL*` |
| prefix | Quit `<leader>q` vs quickfix `<leader>qq`/`ql` | Quit `<leader>Q`; quickfix retains `<leader>q*` |
| prefix | Save `<leader>w` vs viewport `<leader>wv`/`wn`/`ws` | Save retains `<leader>w`; viewport `<leader>vv`/`vn`/`vs` |

### Owner-Qualified Migration

| Owner | Old | New |
|---|---|---|
| OpenCode ask | `<leader>aoa` | `<leader>aa` |
| OpenCode implement | `<leader>aoi` | `<leader>ai` |
| OpenCode actions | `<leader>aox` | `<leader>ax` |
| Noice persistent messages | `<leader>mp` | `<leader>mP` |
| Obsidian pending tasks | `<leader>tt` | `<leader>oP` |
| Obsidian completed tasks | `<leader>tc` | `<leader>oC` |
| Mini trim trailing whitespace | `<leader>tw` | `<leader>xw` |
| Mini trim last empty lines | `<leader>tl` | `<leader>xl` |
| Typst watch/preview | `<leader>tw` | `<leader>Tw` |
| Typst compile | `<leader>tc` | `<leader>Tc` |
| Typst open PDF | `<leader>to` | `<leader>To` |
| Kulala send/toggle/next/previous/inspect/environment/copy/replay/all/scratch/close/schema | `<leader>Rs/Rt/Rn/Rp/Ri/Re/Rc/Rr/Ra/RS/Rq/RG` | `<leader>Hs/Ht/Hn/Hp/Hi/He/Hc/Hr/Ha/HS/Hq/HG` |
| Rust open Cargo | `<leader>Rc` | `<leader>Ro` |
| Diffview line/range history | `<leader>gL` | `<leader>gi` |
| Core quit | `<leader>q` | `<leader>Q` |
| Viewport resize/navigate/select | `<leader>wv/wn/ws` | `<leader>vv/vn/vs` |

No migration alias is approved or documented: old keys are free or belong solely to their surviving owner after source changes land.

## Audit Limits

- Inspected runtime Lua, Vim ftplugins/session, and applicable `AGENTS.md` files. The two Monkey C ftplugins contain no mappings; `Session.vim` contains no mapping definitions.
- Test fixtures that create fake mappings were excluded because they are not runtime configuration.
- This is a source audit, not a dump of `:map`; conditional plugin availability, runtime load order, terminal encoding, and concurrently edited source can change the live effective map.
- Upstream defaults are not invented. Diffview has `disable_defaults = false`, marks.nvim has `default_mappings = true`, blink.pairs enables its mapping set, blink.cmp uses preset `default`, and GitLab retains plugin-default buffer-local UI maps while disabling all default globals. Only keys explicitly named in this repo are inventoried above; unnamed enabled defaults require plugin/runtime inspection.
- which-key-only labels are policy/discovery metadata, not executable mappings, except the explicit `<Nop>` guards inventoried above. Fugitive command-line abbreviations are abbreviations rather than mappings and are outside this inventory.
