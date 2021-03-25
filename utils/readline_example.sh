#!/usr/bin/env bash
# This is an example of how to use the tde readline api
# very simple barebone readline replacement
RED='\033[0;31m'
GREEN='\033[0;32m'
#TDE_HISTORY="abc"

source "tde_readline.sh"

# set the prompt
TDE_READLINE_SUCCESS="tde ${GREEN}➡${NC} "
TDE_READLINE_FAILED="tde ${RED}➡${NC} "
#TDE_COMMENT_COLOR="#FF0000"

# The callback function when a line gets executed
function tde_execute_repl() {
    code="$(echo $1 | sed -E 's/--.*$//g')"
    res="$(echo "if $code == nil then os.exit(1) else print($code) end" | lua -)";
    # if 0 then it was a success
    TDE_REPL_EXIT_CODE="$?"

    echo "$res" | lua /etc/xdg/tde/pretty_print.lua
}

# The callback function when typing (used for colorizing)
function tde_repl_line_callback() {
    echo -en "$1" | lua /etc/xdg/tde/pretty_print.lua
}

# The callback function, should take as a parameter the current line (can be invalid code) and returns a list of possible completion scripts
function tde_repl_code_completion() {
    tde_code_completion_results=("$1" "_G -- the global scope" "1 + 1 -- some aritmatic" "_G -- the global scope" "1 + 1 -- some aritmatic" "_G -- the global scope" "1 + 1 -- some aritmatic" "_G -- the global scope" "1 + 1 -- some aritmatic" "_G -- the global scope" "1 + 1 -- some aritmatic" "_G -- the global scope" "1 + 1 -- some aritmatic")
}

# start repl mode
tde_repl_start

