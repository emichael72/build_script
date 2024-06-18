#!/bin/bash
# tool_box.sh

# ------------------------------------------------------------------------------
# Script Name:    tool_box.sh
# Description:    IMC bash library routines.
# Version:        0.1
# Copyright:      (C) 2018 - 2024 Intel Corporation.
# License:        2018 - 2024 Intel Corporation.
# ------------------------------------------------------------------------------

# Script global variables

toolbox_version="0.1" # Helps to keep track of this glory.
toolbox_allow_debug=0 # Enable / disable the use of 'toolbox_d_printf'
toolbox_terminal_tmi=0 # If true (1_) the step will dump everything to the terminal

##
# @brief Print text with multiple colors in the same line using ANSI color codes.
# @details This function allows dynamic switching of text colors by recognizing
#          certain keywords representing different colors as well as a keyword
#          for resetting to the default terminal color.
# @param COLOR One of the supported color keywords or 'DEFAULT' to reset the color.
# @param "text" The text to print, which can include printf format specifiers.
# @return 0 on success, 1 if invalid color keyword is provided.
# @usage toolbox_c_printf COLOR "text" [COLOR "text" ...]
# @example toolbox_c_printf RED "Error: " YELLOW "Warning level " GREEN "%d\n" 3
# This will print 'Error: ' in red, 'Warning level ' in yellow, and '3' in green,
# followed by a newline.
#

toolbox_c_printf() {

    local DEFAULT='\033[0m'  # Default color reset
    local color="$DEFAULT"
    local segment=""
    local -a args
    local valid_colors="BLACK RED GREEN YELLOW BLUE PURPLE CYAN WHITE DEFAULT"

    # @brief Flush the current segment with color and reset the buffer.
    flush_segment() {
        [[ -n "$segment" ]] && printf "${color}${segment}${DEFAULT}" "${args[@]}"
        segment=""
        args=()
    }

    # @brief Add to the current segment, preserving format specifiers and arguments.
    # @param item The text or format specifier to add to the segment.
    add_to_segment() {
        local item="$1"
        if [[ "$item" =~ %[0-9]*[.]?[0-9]*[diouxXeEfgGcs] ]]; then
            # This is a format specifier
            segment+="$item"
        elif [[ "$segment" =~ %.*[diouxXeEfgGcs] ]]; then
            # This is an argument for the last format specifier
            args+=("$item")
        else
            # This is regular text
            segment+="$item"
        fi
    }

    # Iterate over arguments
    for arg in "$@"; do
        case $arg in
            DEFAULT)
                flush_segment  # Output the current segment before resetting color
                color="$DEFAULT"
                ;;
            BLACK|RED|GREEN|YELLOW|BLUE|PURPLE|CYAN|WHITE)
                flush_segment  # Output the current segment before changing color
                # Set the new color
                case $arg in
                    BLACK) color='\033[0;30m' ;;
                    RED) color='\033[0;31m' ;;
                    GREEN) color='\033[0;32m' ;;
                    YELLOW) color='\033[0;33m' ;;
                    BLUE) color='\033[0;34m' ;;
                    PURPLE) color='\033[0;35m' ;;
                    CYAN) color='\033[0;36m' ;;
                    WHITE) color='\033[0;37m' ;;
                esac
                ;;
            *)
                add_to_segment "$arg"  # Add text or handle as an argument
                ;;
        esac
    done

    flush_segment  # Process any remaining text
    return $?
}

##
# @brief Print formatted debug message.
# @param printf style.
# @return none.
#

toolbox_d_printf() {

     # Exit when this is not enabled.
    if [[ "$toolbox_allow_debug" -eq 0 ]]; then
        return 1
    fi

    local timestamp
    local format_string
    local additional_args

    # Build a time stamp string to be used for the step log file.
    timestamp=$(date +"%m-%d-%Y %H:%M:%S")

    # Extract the format string from the arguments
    format_string="$1"
    shift

    # Print the initial message with timestamp and the associated text
    toolbox_c_printf CYAN "D  " DEFAULT "%-19s: " "$timestamp"   
    toolbox_c_printf YELLOW "$format_string\n" "$@"

    return 0
}

## 
# @brief Ensures a given package is available on the target Linux system using dnf.
# @param $1 package_name The name of the package to be installed or verified.
# @param $2 force_re_install If set to 1, the package will be re-installed even 
#           if already installed; otherwise, it will not re-install.
# @return Returns 0 if the package is installed or successfully installed.
#         Returns 1 if the distribution does not support dnf or package is not available.
#         Returns 3 if uninstalling the package fails.
#         Returns 4 if installing the package fails.
# @details The function operates silently, making use of dnf for package management.
#          It first checks if the package is installed, optionally re-installs it, and ensures
#          the package is available and can be installed if not previously installed.

toolbox_package_installer() {

    local package_name=$1
    local force_re_install=$2
    local package_already_installed=0

    # Detecting the Linux distribution and checking if it uses 'dnf'
    if ! type dnf &>/dev/null; then
        return 1  # Distro not supported
    fi

    # Checking if the package is already installed
    if dnf list --installed "$package_name" &>/dev/null; then
        package_already_installed=1
        if [ "$force_re_install" -ne 1 ]; then
            return 0  # Package is already installed and re-install is not forced
        fi
    fi

    # Re-installation process
    if [ "$package_already_installed" -eq 1 ]; then
        if ! sudo dnf remove -y "$package_name" &>/dev/null; then
            return 3  # Uninstall failure
        fi
    fi

    # Check if the package is available
    if ! dnf list "$package_name" &>/dev/null; then
        return 2  # Package does not exist
    fi

    # Installation process
    if ! sudo dnf install -y "$package_name" &>/dev/null; then
        return 4  # Install failure
    fi

    return 0  # Success
}

##
# @brief print a file size in a nicely formatted way.
# @return 0 on success
#

toolbox_print_file_size() {

    local file="$1"

    if [[ -f "$file" ]]; then
        du -h "$file" | cut -f1
        return 0
    fi

    return 1 # Error
}

##
# @brief Converts a given string to lowercase and replaces spaces with underscores.
# @param input The input string to be converted.
# @return The converted string is printed to standard output.
#

toolbox_convert_to_lower_underscore() {

    local input="$1"
    echo "$input" | tr '[:upper:]' '[:lower:]' | tr ' ' '_'
}

##
# @brief Print a character a specified number of times.
#   This function prints a given character a specified number of times,
#   followed by a newline.
# @param char The character to be printed.
# @param count The number of times to print the character.
#

toolbox_print_char_n_times() {

    local char=$1
    local count=$2
    for ((i=0; i<count; i++)); do
        printf "%s" "$char"
    done
    printf "\n\n"
}

##
# @brief Print text with a specified byte count per line.
#   This function reads the input text and prints it, ensuring that each line
#   does not exceed the specified byte count. If a line is longer than the
#   specified byte count, it is wrapped to the next line.
# @param text The text to be printed, provided as a single string.
# @param bytes_per_line The number of bytes per line to enforce.
#

toolbox_print_wrapped() {

    local text=$1
    local bytes_per_line=$2

    while IFS= read -r line; do
        while [[ ${#line} -gt $bytes_per_line ]]; do
            printf "%.*s\n" $bytes_per_line "$line"
            line=${line:$bytes_per_line}
    done
    printf "%s\n" "$line"
    done <<< "$text"
}

##
# @brief Count the occurrences of a specific word in a text file.
#  @param file_path The path to the text file.
#  @param word The word to count in the text file.
#  @retval 0 if the file path is not provided,
#           the file is not readable, or the word is not provided.
#  @retval The number of times the word appears in the file, if successful.
#

toolbox_count_word_occurrences() {

    local file_path="$1"
    local word="$2"

    # Combined checks for file path, file readability, and word presence
    if [[ -z "$file_path" || ! -r "$file_path" || -z "$word" ]]; then
        echo 0
    fi

    # Remove ANSI escape sequences and count the occurrences of the word
    local count
    count=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$file_path" | grep "$word" | wc -l)
    echo $count
}


##
# @brief Convert a relative path to an absolute path.
# @param[in] relative_path The relative path to be converted.
# @return The absolute path corresponding to the given relative path.
#

toolbox_to_absolute_path() {

    local relative_path="$1"
    local absolute_path  

    # Use readlink to resolve the absolute path
    absolute_path=$(readlink -f "$relative_path")

    echo "$absolute_path"
}

##
# @brief Cleans ANSI escape codes from the provided string.
# This function processes the input string and removes ANSI escape codes,
# including long-form RGB codes, non-movement/color codes, and movement/color codes.
#
# @param input_string The string containing potential ANSI escape codes.
# @return The cleaned string without ANSI escape codes.
#
#

toolbox_clean_ansi_escape_codes() {

    local input_string="$1"

    # Remove ANSI escape codes
    input_string=$(echo "$input_string" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    input_string=$(echo "$input_string" | sed -r 's/\x1B\([0-9;]*[a-zA-Z]//g')
    input_string=$(echo "$input_string" | sed -r 's/\x1B\][0-9;]*//g')
    input_string=$(echo "$input_string" | sed -r 's/\x1B[()#][0-9;]*[a-zA-Z]//g')
    input_string=$(echo "$input_string" | sed -r 's/\x1B\][^\x1B]*\x1B\\//g')
    input_string=$(echo "$input_string" | sed -r 's/\x1B[^a-zA-Z]*[a-zA-Z]//g')

    echo "$input_string"
}


##
# @brief Extracts the filename that caused the GCC compilation error from the 
#        provided GCC output.
# This function processes GCC compilation output assumed not to have ANSI escape 
# codes, and extracts the filename of the source file that caused the 
# compilation error. It returns an empty string if no error is found or if the 
# extraction fails.
# @param gcc_output The string containing GCC console output.
# @return The filename with its path if found, or an empty string if an error 
# occurs or file doesn't exist.
#

toolbox_prase_gcc_output() {

    
    local gcc_output="$1"

    # Ensure gcc_output is a single line (remove newlines and carriage returns)
    gcc_output=$(echo "$gcc_output" | tr -d '\n' | tr -d '\r')

    # Search for the pattern ":num:num: error:"
    if [[ $gcc_output =~ ([^:]*):([0-9]+):([0-9]+):\ error: ]]; then
        local file_path="${BASH_REMATCH[1]}"

        # Check if the file path has a valid extension
        if [[ $file_path =~ \.([ch])$|\.s$ ]]; then
            # Final check if the file exists
            if [[ -f "$file_path" ]]; then
                echo "$file_path"
                return 0
            fi
        fi
    fi

    # Return empty string on error.
    echo ""
    return 1
}

## @brief Handles errors by checking the provided step index, log file name, and return value.
#         If AI-assisted error handling is enabled in the JSON configuration, it processes the 
#         log file content.
# @param $1 step_index The index of the step that encountered an error.
# @param $2 step_log_file_name The name of the log file for the step.
# @param $3 step_return_value The return value of the step.
# @param $4 get_ai_assisted_error_info - fetch insights from an AI, boolean (0|1)
# 
# @return Returns 1 if there are incorrect arguments or if the AI-assisted error 
#         handling is not enabled in the JSON configuration. Otherwise, it returns 
#         the original step return value.
# @details This function first checks if the correct number of arguments are 
#          provided and if they are not null.
#          It then checks if AI-assisted error handling is enabled. If not, it 
#          directly returns the original step return value. If enabled, it proceeds 
#          to analyze the log file to determine the error's
#          source file and content, calling a Python script for AI insights if necessary.
#

toolbox_error_handler() {

    local step_index=$1
    local step_log_file_name=$2
    local step_return_value=$3
    local ai_assisted=$4
    local ai_assist_timeout=$5
    local bad_source_file_name
    local bad_source_file_content
    local gcc_error_message

    # Check if exactly three arguments are passed
    if [ "$#" -ne 5 ]; then        
        return 1 # Error: Exactly 4 arguments are required
    fi

    # Check if any of the arguments are null
    if [ -z "$step_index" ] || [ -z "$step_log_file_name" ] || [ -z "$step_return_value" ] || [ -z "$ai_assisted" ]; then
        return 1 # Error: All arguments must be non-null
    fi

    # Check if AI assist is enabled
    if [ "$ai_assisted" -eq 0 ]; then
         return $step_return_value # Not enabled
    fi

    # Read and clean the content of the log file into a variable
    gcc_error_message=$(toolbox_read_file_to_variable "$step_log_file_name" 1)
    status=$?
    if [[ $status -eq 1 ]]; then
        return $step_return_value # Error: Problematic Log file.s
    fi
    
    # Extract the file that triggered the error
    bad_source_file_name=$(toolbox_prase_gcc_output "$gcc_error_message")
    
    # Verify that the file exists and read its content into bad_source_file_content
    if [ -n "$bad_source_file_name" ]; then
        if [ -f "$bad_source_file_name" ]; then
            raw_file_content=$(toolbox_read_file_to_variable "$bad_source_file_name" 1)
            status=$?
            if [[ $status -eq 1 ]]; then
                return $step_return_value # Error: Problematic source file.
            fi
        else
            return $step_return_value # Error: File does not exist.
        fi
    else
        return $step_return_value # Error: No valid source file name found in the error message.
    fi

    # Call the Python script
    toolbox_c_printf "\nCompilation " RED "error" DEFAULT " found in '" CYAN "$bad_source_file_name'" DEFAULT "\n"
    toolbox_c_printf "Requesting AI assistance....\n\n\n"
    insights=$(/usr/bin/python3 $script_base_path/ai_insights.py "$gcc_error_message" "$bad_source_file_content" "$ai_assist_timeout")
    echo "$insights"

    return $step_return_value
}

##
# @brief Extract an argument from a JSON file and test if it correlates to one
#        of the provided options.
# @param json_file: JSON file to parse.
# @param json_arg: The argument to look for.
# @param options: A list of valid options.
# 
# Prerequisite : 'jq' utility.
# @return The index (base 0) of the found option.
# The script will exit if the value was not extracted or is invalid.
#

toolbox_extract_json_arg() {

    local json_file="$1"
    local json_arg="$2"
    shift 2
    local options=("$@")
    local value
    local index=0

    # Ensure jq is installed
    if ! command -v jq &> /dev/null; then
         toolbox_c_printf RED "Error: " DEFAULT "'jq' is not installed, try 'sudo dnf install jq'\n" >&2
        exit 1
    fi

    # Ensure the JSON file exists and is readable
    if [[ ! -r "$json_file" ]]; then
         toolbox_c_printf RED "Error: " DEFAULT "'$json_file' does not exist or is not readable.\n" >&2
        exit 1
    fi

    # Extract the argument from the JSON
    value=$(jq -r --arg arg "$json_arg" '.[$arg]' "$json_file")

    if [[ -z "$value" || "$value" == "null" ]]; then
        toolbox_c_printf RED "Error: " DEFAULT "'$json_arg' not found or invalid in '$json_file'.\n" >&2
        exit 1
    fi

    # Convert value to lower case
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    # Iterate over options array to find the value
    for option in "${options[@]}"; do
        option=$(echo "$option" | tr '[:upper:]' '[:lower:]')
        if [[ "$value" == "$option" ]]; then
            return $index
        fi
        ((index++))
    done

    # If value not found in options, exit with error
    toolbox_c_printf RED "Error: " DEFAULT "'$json_arg' value in '$json_file'. Expected one of ${options[*]}, but found '$value'.\n" >&2
    exit 1
}

##
# @brief Reads the content of a file and returns it as a variable.
#
# This function checks if the specified file exists and is not empty. If the file 
# exists and is not empty, it reads the file content into a variable and prints it. 
# If the clean_ansi argument is true (1), the content is passed through the 
# toolbox_clean_ansi_escape_codes function.
# The function returns specific exit codes to indicate different error conditions.
#
# @param[in] file_path The path to the file to be read.
# @param[in] clean_ansi Boolean flag to determine if ANSI escape codes should be removed.
# @return 0 if the file is read successfully.
# @return 1 if the file does not exist.
# @return 2 if the file is empty.

toolbox_read_file_to_variable() {

    local file_path="$1"
    local clean_ansi="$2"

    if [[ ! -f "$file_path" ]]; then
        return 1 # File does not exist
    elif [[ ! -s "$file_path" ]]; then
        return 2 # File is empty
    else
        # Read the file content into a variable using `cat`
        local file_content
        file_content=$(cat "$file_path")

        # If clean_ansi is true, clean ANSI escape codes from the content
        if [[ "$clean_ansi" -eq 1 ]]; then
            file_content=$(toolbox_clean_ansi_escape_codes "$file_content")
        fi

        # Output the content to a global variable
        printf "%s" "$file_content"
        return 0
    fi
}

##
# @brief Executes a single step based on the provided steps table and return the
#        executed command return value.
# @param steps table
# @param the index of the step to execute.
# @note This function aims to generate a human-readable console trace.
#       As a result, it has become more complex than originally intended.
# @return int : The return code of the executed command.
#

toolbox_exec_step() {

    local -n build_steps=$1
    local index="$2"
    local timestamp
    local step
    local description
    local command
    local file_name
    local logfile
    local warnings_count="0"
    local initial_message

    if [ ${index} -ge ${#steps[@]} ]; then
        declare -g toolbox_last_log_file=""
        toolbox_c_printf RED "Error:" DEFAULT "Invalid step.\n"
        return 0
    fi

     # Extract the specified step
    step="${build_steps[$index]}"

    # Split the step into description and execution string
    description=$(echo "$step" | cut -d "'" -f 2)
    command=$(echo "$step" | cut -d "'" -f 4)

    # Expand the command
    command=$(eval echo "$command")

    toolbox_d_printf "Command: %s" "$command"
   
    # Construct a file name out the step discretion.
    file_name=$(toolbox_convert_to_lower_underscore "$description")

    # Check if any of the variables are null
    if [ -z "$description" ] || [ -z "$command" ] || [ -z "$file_name" ]; then
        toolbox_c_printf RED "Error: " DEFAULT "One or more step input variables are null.\n"
        exit 1 # Critical: problematic steps table.
    fi

    # Build a time stamp string to be used of the step log file.
    timestamp=$(date +"%d_%m_%Y_%H_%M_%S")
    logfile="$log_files_path/${index}_${file_name}_${timestamp}.log"
    mkdir -p ${log_files_path} > /dev/null 2>&1 # Make sure the path exists

    # Store last log file name globally, this will come in handy if we
    # need to open the last log in case of an error.
    declare -g toolbox_last_log_file="$logfile"
   
    # Print the initial message with timestamp and the associated text
    initial_message="$(printf "%-2d %-19s: %-s " "$index" "$(date +"%m-%d-%Y %H:%M:%S")" "$description")"

    # Fixed length for the entire line
    local fixed_length=70
    local message_length=${#initial_message}
    local status_length=6  # Length of the status message " OK\n"
    local dots_needed=$((fixed_length - message_length - status_length ))

    # Ensure dots_needed is not negative
    dots_needed=$((dots_needed > 0 ? dots_needed : 0))
    local dots=$(printf '%*s' "$dots_needed" '' | tr ' ' '.')

    # If we're set to output everything to the terminal..
    if [[ "$toolbox_terminal_tmi" -eq 1 ]]; then
        # Execute the command with verbose output
        eval "$command"
        local ret_val=$?
    else
        # Execute the command silently, redirecting output to a log file
        printf "%s%s" "$initial_message" "$dots"
        eval "$command" &> "$logfile"
        local ret_val=$?

        # Count the times the ward "warning" appeared in the output file.
        warnings_count=$(toolbox_count_word_occurrences "$logfile" "warning:")
    fi

    if [ $ret_val -eq 0 ]; then
        if [[ "$toolbox_terminal_tmi" -eq 0 ]]; then
            if [ "$warnings_count" != "0" ]; then
                toolbox_c_printf GREEN " OK " YELLOW "($warnings_count)" DEFAULT "\n"
            else
                toolbox_c_printf GREEN " OK \n"
            fi
        fi
    else
        if [[ "$toolbox_terminal_tmi" -eq 0 ]]; then
            toolbox_c_printf RED " Error ($ret_val) \n"
        else
            toolbox_c_printf RED "Error ($ret_val) \n"
        fi
    fi

    # Pass on the global step handler
    if [ "$ret_val" -ne 0 ]; then
        toolbox_error_handler $index $logfile $ret_val $ai_assisted_error_info $ai_assisted_timeout
    fi

    return $ret_val
}


##
# @brief Sets the global options for allow_debug and extensive terminal output.
# @param[in] allow_debug Boolean flag to allow debug (0 or 1).
# @param[in] terminal_tmi Boolean flag to allow terminal TMI (0 or 1).
# @return 0 or 1.

toolbox_set_options() {

    local allow_debug="$1"
    local terminal_tmi="$2"

    # Validate parameters
    if [[ "$allow_debug" != 0 && "$allow_debug" != 1 ]]; then
        return 1
    fi

    if [[ "$terminal_tmi" != 0 && "$terminal_tmi" != 1 ]]; then
        return 1
    fi

    # Set global variables
    toolbox_allow_debug="$allow_debug"
    toolbox_terminal_tmi="$terminal_tmi"

    return 0
}