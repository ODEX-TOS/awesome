#!/bin/bash

# configurable history
__tde_history_file=${TDE_HISTORY:-"$HOME/.tde-client_history"}
# update the active code_completion list
declare -a tde_code_completion_results=('N/A')

TDE_READLINE_SUCCESS=${TDE_READLINE_SUCCESS:-"tde ${GREEN}➡${NC} "}
TDE_READLINE_FAILED=${TDE_READLINE_FAILED:-"tde ${RED}➡${NC} "}
TDE_REPL_EXIT_CODE="0"

TDE_FOREGROUND_COLOR=${TDE_FOREGROUND_COLOR:-"#bd93f9"}
TDE_BACKGROUND_COLOR=${TDE_BACKGROUND_COLOR:-"#282a36"}
TDE_BACKGROUND_SELECT_COLOR=${TDE_BACKGROUND_SELECT_COLOR:-"#44475a"}
TDE_COMMENT_COLOR=${TDE_COMMENT_COLOR:-"#6272a4"}

# internal variables
__code_completion_length="50"
tde_readline=""
TDE_HIST_INDEX="$(cat $__tde_history_file | wc -l)"
MAX_TDE_HIST_INDEX="$TDE_HIST_INDEX"

### START of overwritable functions
function tde_execute_repl() {
    echo "Executing: $1"
}

# This function gets called each time the current line gets modified
function tde_repl_line_callback() {
    echo -en "$1"
}

# This function gets called each time the code_completion could potentially get updated
# Note: this can get called a lot, make sure the execution happens fast, otherwise it might impact the user performance
# Note: you need to update the var tde_code_completion_results (bash array) with a list of all possible completions
function tde_repl_code_completion() {
    tde_code_completion_results=("$1 -- the current input")
}
### END of overwritable functions



# Internal functions start here

function __tde_repl_line_callback() {
    printf "\e[0m"
    if [[ "$TDE_REPL_EXIT_CODE" == "0" ]]; then
        echo -en "\r$TDE_READLINE_SUCCESS"
    else
        echo -en "\r$TDE_READLINE_FAILED"
    fi

    if [[ "$1" == "" ]]; then
        return
    fi
    tde_repl_line_callback "$1" | tr -d '\n'
}

function __tde_get_cursor_pos() {
    stty -echo
    echo -ne $'\e[6n'
    read -d R x
    stty echo
    __tde_x=$(echo ${x#??} | cut -d';' -f1)
    __tde_y=$(echo ${x#??} | cut -d';' -f2)

    re='^[0-9]+$'

    if [[ -z "$__tde_x" || ! "$__tde_x" =~ "$re" ]]; then
        __tde_x="1"
    fi
    if [[ -z "$__tde_y" || ! "$__tde_y" =~ "$re" ]]; then
        __tde_y="1"
    fi
}

function __tde_set_cursor_pos() {
    tput cup "$1" "$2"
}

function __tde_parse_hex_color() {
    local r="${1:1:2}"
    local g="${1:3:2}"
    local b="${1:5:2}"
    __tde_red=$(printf "%d" "0x$r")
    __tde_green=$(printf "%d" "0x$g")
    __tde_blue=$(printf "%d" "0x$b")
}

function __tde_setup_colors() {
    # set the color
    __tde_parse_hex_color "$TDE_FOREGROUND_COLOR"
    fg_r="$__tde_red"
    fg_g="$__tde_green"
    fg_b="$__tde_blue"

    __tde_parse_hex_color "$TDE_BACKGROUND_COLOR"
    bg_r="$__tde_red"
    bg_g="$__tde_green"
    bg_b="$__tde_blue"

    __tde_parse_hex_color "$TDE_BACKGROUND_SELECT_COLOR"
    bg_cur_r="$__tde_red"
    bg_cur_g="$__tde_green"
    bg_cur_b="$__tde_blue"

    __tde_parse_hex_color "$TDE_COMMENT_COLOR"
    comment_r="$__tde_red"
    comment_g="$__tde_green"
    comment_b="$__tde_blue"
}

function __tde_draw_code_completion_line() {
    local str="${@:2}"
    # strip down string when it becomes to large
    str="${str:0:$(( __code_completion_length - 4))}"
    if [[ "${#str}" -ge "$(( __code_completion_length - 4 ))" ]]; then
        str="$str... "
    fi

    # set the foreground
    printf "\e[38;2;$fg_r;$fg_g;${fg_b}m"

    # we are printing an active line
    if [[ "$1" == "1" ]]; then
        printf "\e[48;2;$bg_cur_r;$bg_cur_g;${bg_cur_b}m"
    else
        # we are printing a non active line
        printf "\e[48;2;$bg_r;$bg_g;${bg_b}m"
    fi
    printf "  %s %*s\e[0m" "$(echo "$str" | sed "s/--/\o033[38;2;${comment_r};${comment_g};${comment_b}m--/" )" "$(( __code_completion_length - ${#str} ))"
}

# draw a code_completion box at the location of the cursor
# $@ are all the elements in the code_completion box
function __tde_draw_code_completion_box() {
    # save the current cursor location
    __tde_get_cursor_pos
    local x_orig="$(( __tde_x - 1))"
    local y_orig="$(( __tde_y - 1 ))"
    # for each line create an entry in the code_completion box
    local i="0"
    local lines_drawn="0"
    local enabled="0"
    for line in "${tde_code_completion_results[@]}"; do
        # our selection is always first
        if [[ "$i" -lt "$1" ]]; then
            i="$(( i + 1))"
            continue
        else
           lines_drawn="$(( lines_drawn + 1))" 
        fi

        if [[ "$lines_drawn" -gt "10" ]]; then
            break
        fi

        # only draw the next 10 lines
        # move one line down
        __tde_x="$(( __tde_x + 1 ))"
        i="$(( i + 1 ))"
        __tde_set_cursor_pos "$__tde_x" "$__tde_y"

        enabled="0"
        if [[ "$1" == "$i" ]]; then
            enabled="1"
        fi

        # draw the line
        __tde_draw_code_completion_line "$enabled" "$line"
    done

    # restore the location back to the saved location
    __tde_set_cursor_pos "$x_orig" "$y_orig"
}

function __tde_repl_execute_callback() {
    if [[ "$tde_readline" == "" ]]; then
        return
    fi

    # executing line -> adding to the history
    echo "$tde_readline" >> "$__tde_history_file"
    MAX_TDE_HIST_INDEX=$(( MAX_TDE_HIST_INDEX + 1 ))
    TDE_HIST_INDEX="$MAX_TDE_HIST_INDEX"

    echo
    tde_execute_repl "$tde_readline"

}

function __tde_handle_key_edge_case() {
    __TDE_ASCII_CODE="$(LC_CTYPE=C printf '%d' "'$1")"
    if [[ "$__TDE_ASCII_CODE" == "12" ]]; then
        clear
        tde_readline=""
    elif [[ "$__TDE_ASCII_CODE" == "4" ]]; then
        exit 0
    elif [[ "$__TDE_ASCII_CODE" == "21" ]]; then
        tde_readline=""
    else
        echo "Illegal argument '$1'"
        LC_CTYPE=C printf 'ASCII: %d\n' "'$1"
    fi
}

function __tde_readline_handle_autocompletion() {
    clear
    local INDEX="0"
    __tde_repl_line_callback "${tde_readline}"
    while true; do
        IFS= read -r -sN1 ans
        # catch multi-char special key sequences
        IFS= read -sN1 -t 0.003 k1
        IFS= read -sN1 -t 0.003 k2
        IFS= read -sN1 -t 0.003 k3
        ans+=${k1}${k2}${k3}
        clear
        case "$ans" in
            $'\e[A'|$'\e0A'|$'\e[D'|$'\e0D')  # cursor up, left: previous item
                INDEX=$((INDEX - 1))
                if [[ "$INDEX" -le 0 ]]; then
                    INDEX="0"
                fi
                __tde_repl_line_callback "${tde_code_completion_results[$(( INDEX - 1 ))]}"
            ;;
            $'\e[B'|$'\e0B'|$'\e[C'|$'\e0C')  # cursor down, right: next item
                INDEX=$((INDEX + 1))
                
                if [[ "$INDEX" -ge "${#tde_code_completion_results}" ]]; then
                    INDEX="${#tde_code_completion_results}"
                fi
                __tde_repl_line_callback "${tde_code_completion_results[$(( INDEX - 1 ))]}"
            ;;
            $'\177')
                if [[ "${#tde_readline}" -ge "1" ]]; then
                    tde_readline="${tde_readline::-1}"
                fi
            ;;
            $'\012')
                if [[ "$INDEX" == "0" ]]; then
                    break
                fi
                __tde_repl_line_callback "${tde_code_completion_results[$(( INDEX - 1 ))]}"

                tde_readline="${tde_code_completion_results[$(( INDEX - 1 ))]}"
                INDEX="0"
            ;;
            *[![:cntrl:]]*)
                tde_readline="${tde_readline}${ans}"
                updated_line="1"
            ;;
            **)
                __tde_handle_key_edge_case "$ans"
            ;;
        esac
        tde_repl_code_completion "$tde_readline"
        __tde_repl_line_callback "${tde_readline}"
        if [[ "$tde_readline" != "" ]]; then
            __tde_draw_code_completion_box "$INDEX"
        else
            break
        fi
    done
}


# This function starts the repl mode
function tde_repl_start() {
    printf "\e[0m"
    echo -en "$TDE_READLINE_SUCCESS"
    __tde_setup_colors
    while true; do
        IFS= read -r -sN1 ans
        # catch multi-char special key sequences
        IFS= read -sN1 -t 0.0001 k1
        IFS= read -sN1 -t 0.0001 k2
        IFS= read -sN1 -t 0.0001 k3
        ans+=${k1}${k2}${k3}
        case "$ans" in
            $'\e[A'|$'\e0A'|$'\e[D'|$'\e0D')  # cursor up, left: previous item
                clear
                TDE_HIST_INDEX="$(( TDE_HIST_INDEX - 1 ))"
                if [[ "$TDE_HIST_INDEX" -lt 0 ]]; then
                    TDE_HIST_INDEX="0"
                fi
                # update the line to match the history
                tde_readline="$(cat $__tde_history_file | head -n${TDE_HIST_INDEX} | tail -n1)"
                updated_line="0"
            ;;
            $'\e[B'|$'\e0B'|$'\e[C'|$'\e0C')  # cursor down, right: next item
                clear
                TDE_HIST_INDEX="$(( TDE_HIST_INDEX + 1 ))"
                if [[ "$TDE_HIST_INDEX" -gt "$MAX_TDE_HIST_INDEX" ]]; then
                    TDE_HIST_INDEX="$MAX_TDE_HIST_INDEX"
                fi
                # update the line to match the history
                tde_readline="$(cat $__tde_history_file | head -n${TDE_HIST_INDEX} | tail -n1)"
                updated_line="0"
            ;;
            $'\177')
                if [[ "${#tde_readline}" -ge "1" ]]; then
                    tde_readline="${tde_readline::-1}"
                fi
                updated_line="0"
            ;;
            $'\012')
                __tde_repl_execute_callback
                tde_readline=""
                updated_line="0"
            ;; 
            *[![:cntrl:]]*)
                tde_readline="${tde_readline}${ans}"
                updated_line="1"
            ;;
            **)
                __tde_handle_key_edge_case "$ans"
            ;;
        esac
        
        __tde_repl_line_callback "$tde_readline"
        
        if [[ "$tde_readline" != "" && "$updated_line" == "1" ]]; then
            tde_repl_code_completion "$tde_readline"
            __tde_readline_handle_autocompletion "$tde_readline"

            #clear

            __tde_repl_execute_callback

            tde_readline=""
            updated_line="0"
            
            __tde_repl_line_callback "$tde_readline"

        fi
    done
}
