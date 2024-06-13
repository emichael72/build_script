#!/bin/bash
# mev_imc_build_app.sh

# ------------------------------------------------------------------------------
# Script Name:    mev_imc_build_app.sh
# Description:    IMC Application build script.
# Version:        0.1
# Usage:          ./mev_imc_build_app.sh -?
# Copyright:      (C) 2018 - 2024 Intel Corporation.
# License:        2018 - 2024 Intel Corporation.
# ------------------------------------------------------------------------------

# Notes:
# ------

# This script executes the steps required to successfully create the necessary
# CMake files for the application. After this, it builds all the necessary
# project sections and finally links them to the 'Zephyr' binary. The script
# can build for either Simics or Veloce platforms, in either release or debug
# profiles, depending on the caller inputs.
#
# 1. The script can be executed using command line arguments or by providing a
#    specifically structured JSON file.
# 2. Each step stores its output in the 'logs' folder for later inspection.
# 3. Any error in any of the steps will result in the execution terminating and
#    returning to the terminal.
# 4. The script will parse each step's log file and check for warnings. If the
#    count of warnings is greater than 0, it will be printed next to the step
#    summary.
# 5. The script is one building block among others, consequently some of its
#    inputs are gathered from the shell environment.
# 6. Script is documented using Doxygen style, not very common but why not.
# 
# JSON file expected format:
: '
    {
        "app_source_path"           : "$trunk/sources/imc/zephyr/apps/imc_init_app/",
        "cmake_template_file"       : "toolchain_template.cmake",
        "source_nvm_file_name"      : "$trunk/sources/imc/nvm-generator/Simics_10003/nvm-image_10003.bin",
        "destination_nvm_file_name" : "$trunk/sources/imc/nvm-generator/Simics_10003/nvm-image_10003_eitan.bin",
        "nvm_auto_inject"           : true,
        "build_target"              : "SiMics",
        "build_type"                : "debug",
        "no_pre_clean"              : false,
        "skip_ft_id"                : false,
        "start_fresh"               : false,
        "clean_zephyr"              : false,
        "script_show_debug"         : false,
        "script_chatty"             : false,
        "clear_logs"                : true,
        "make_zephyr_only"          : true
    }

'

# Script global variables

script_version="0.1" # Helps to keep track of this glory.

# Bit mask values for allowing any combination of input arguments
BUILD_OPT_SIMICS=$((0x01))              # Build for Simics
BUILD_OPT_VELOCE=$((0x02))              # Build for Veloce
BUILD_OPT_DEBUG=$((0x04))               # Debug build
BUILD_OPT_RELEASE=$((0x08))             # Release build
BUILD_OPT_MAKE_CLEAN=$((0x10))          # Force 'make clean; prior to build
BUILD_OPT_SKIP_FT_GENERATION=$((0x20))  # Skip FT - ID generation.
BUILD_OPT_START_FRESH=$((0x40))         # Clears the build path prior to compilation.
BUILD_OPT_FAST_MAKE=$((0x80))           # Simply call 'make' (a Makefile must exist)
BUILD_OPT_SCRIPT_SHOW_DEBUG=$((0x100))  # Allow for debug string to be printed
BUILD_OPT_SCRIPT_CHATTY=$((0x200))      # Dump everything to the terminal instead of a log files.
BUILD_OPT_CLEAR_LOGS=$((0x400))         # Clear step logs

# Variable to hold selected arguments along with few defaults.
script_args=$((script_args | BUILD_OPT_SIMICS | BUILD_OPT_CLEAR_LOGS))

export_config_script_name="export_kernel_build_config.sh"
toolchain_template_file="toolchain_template.cmake" # Template being use in-conjunction with CMake.
toolchain_cmake_file="toolchain.cmake" # The CMake file we'd be using.
log_files_path="logs" # Where we store our run-time per step logs.
compiled_binary_name="zephyr.bin" # Expected compilation product upon success.
application_source_path="" # Script expected essential argument.
last_log_file="" # Last created log file.
last_step_index=0 # Keep track of the currently executed step.
build_platform="" # Caller selected target build platform could be Simics' or 'Veloce'.
build_type="" # Caller selected compilation profile 'Debug' or 'Release'.
json_file_name="" # The JSON file name in the case we're using JSON
source_nvm_file_name="" # The source NVM file (untouched by this script).
destination_nvm_file_name="" # The updated NVM file name we're about to crate using 'inject'
script_base_path="" # Script base execution path 
build_path="" # Target build folder

# Script global execution step array.
declare -a steps=(
    # Step description                      Execution operation                                                           Step #
    #---------------------------------------------------------------------------------------------------------------------------
    "'Export kernel build configuration'    '\${export_config_script_name} \${build_path}'"                                  # 0
    "'Generate CMake tool-chain file'       'cmake_generate_toolchain_file \${toolchain_template_file}'"                     # 1
    "'Configure CMake'                      'configure_cmake'"                                                               # 2
    "'Quick Zephyr make'                    'make'"                                                                          # 3
    "'Generating ID'                        'python3 \${IMC_FT_TOOLS_DIR}/ft_id_generator.py --path . -r 4'"                 # 4
    "'Building MEV Infra lib'               'make -C \"\$MEV_INFRA_PATH\" -j\$(nproc)'"                                      # 5
    "'Building MEV-TS lib'                  'make -C \"\$MEV_LIBS_PATH\" -j\$(nproc)'"                                       # 6
    "'Building Infra Common lib'            'make -C \"\$IMC_INFRA_COMMON_LINUX_DIR\" -j\$(nproc)'"                          # 7
    "'Quick Zephyr clean'                   'make clean'"                                                                    # 8
    "'Building Zephyr'                      'cmake --build \"\${build_path}\" -j\$(nproc)'"                                  # 9
    "'Quick Zephyr link'                    'make -f CMakeFiles/linker.dir/build.make'"                                      # 10
    "'NVM file Inject'                      'python3 mgv_imc_image_injection.py -nvm \${source_nvm_file_name} -z \${compiled_binary_name} -o \${destination_nvm_file_name}'" # 11
)

##
# @brief Print text with multiple colors in the same line using ANSI color codes.
# @details This function allows dynamic switching of text colors by recognizing
#          certain keywords representing different colors as well as a keyword
#          for resetting to the default terminal color.
# @param COLOR One of the supported color keywords or 'DEFAULT' to reset the color.
# @param "text" The text to print, which can include printf format specifiers.
# @return 0 on success, 1 if invalid color keyword is provided.
# @usage c_printf COLOR "text" [COLOR "text" ...]
# @example c_printf RED "Error: " YELLOW "Warning level " GREEN "%d\n" 3
# This will print 'Error: ' in red, 'Warning level ' in yellow, and '3' in green,
# followed by a newline.
#

c_printf() {

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
# @brief print a file size in a nicely formatted way.
# @return 0 on success
#

text_print_file_size() {

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

text_convert_to_lower_underscore() {

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

text_print_char_n_times() {

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

text_print_wrapped() {

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

text_count_word_occurrences() {

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
# @brief Print formatted debug message.
# @param printf style.
# @return none.
#

debug_print() {

     # Exit when 'show debug bit' is off.
    if (( (script_args & BUILD_OPT_SCRIPT_SHOW_DEBUG) == 0 )); then
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
    c_printf CYAN "D  " DEFAULT "%-19s: " "$timestamp"   
    c_printf YELLOW "$format_string\n" "$@"

    return 0
}

##
# @brief Convert a relative path to an absolute path.
# @param[in] relative_path The relative path to be converted.
# @return The absolute path corresponding to the given relative path.
#

to_absolute_path() {

    local relative_path="$1"
    local absolute_path  

    # Use readlink to resolve the absolute path
    absolute_path=$(readlink -f "$relative_path")

    echo "$absolute_path"
}

##
# @brief Executes a single step based on the global steps table and return the
#        executed command return value.
# @param the index of the step to execute.
# @note This function aims to generate a human-readable console trace.
#       As a result, it has become more complex than originally intended.
# @return int : The return code of the executed command.
#

execute_step() {

    local index="$1"
    local timestamp
    local step
    local description
    local command
    local file_name
    local logfile
    local warnings_count="0"
    local initial_message

    if [ ${last_step_index} -ge ${#steps[@]} ]; then
        c_printf RED "Error:" DEFAULT "All steps completed.\n"
        return 0
    fi

     # Extract the specified step
    step="${steps[$index]}"

    # Split the step into description and execution string
    description=$(echo "$step" | cut -d "'" -f 2)
    command=$(echo "$step" | cut -d "'" -f 4)

    # Expand the command
    command=$(eval echo "$command")

    debug_print "Command: %s" "$command"
   
    # Construct a file name out the step discretion.
    file_name=$(text_convert_to_lower_underscore "$description")

    # Check if any of the variables are null
    if [ -z "$description" ] || [ -z "$command" ] || [ -z "$file_name" ]; then
        c_printf RED "Error: " DEFAULT "One or more step input variables are null.\n"
        exit 1 # Critical: problematic steps table.
    fi

    # Build a time stamp string to be used of the step log file.
    timestamp=$(date +"%d_%m_%Y_%H_%M_%S")
    logfile="$log_files_path/${index}_${file_name}_${timestamp}.log"
    mkdir -p ${log_files_path} > /dev/null 2>&1 # Make sure the path exists

    # Store last log file name globally, this will come in handy if we
    # need to open the last log in case of an error.
    last_log_file=$logfile

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
    if (( (script_args & BUILD_OPT_SCRIPT_CHATTY) != 0 )); then
        # Execute the command with verbose output
        eval "$command"
        local ret_val=$?
    else
        # Execute the command silently, redirecting output to a log file
        printf "%s%s" "$initial_message" "$dots"
        eval "$command" &> "$logfile"
        local ret_val=$?

        # Count the times the ward "warning" appeared in the output file.
        warnings_count=$(text_count_word_occurrences "$logfile" "warning:")
    fi

    if [ $ret_val -eq 0 ]; then
        if (( (script_args & BUILD_OPT_SCRIPT_CHATTY) == 0 )); then
            if [ "$warnings_count" != "0" ]; then
                c_printf GREEN " OK " YELLOW "($warnings_count)" DEFAULT "\n"
            else
                c_printf GREEN " OK \n"
            fi

            # Update the global step index
            last_step_index=$index
        fi
    else
        if (( (script_args & BUILD_OPT_SCRIPT_CHATTY) == 0 )); then
            c_printf RED " Error ($ret_val) \n"
        else
            c_printf RED "Error ($ret_val) \n"
        fi
    fi

    return $ret_val
}

##
# @brief Extract an argument from a JSON file and test if it correlates to one
#        of the provided options.
# @param json_file: JSON file to parse.
# @param json_arg: The argument to look for.
# @param options: A list of valid options.
# @return The index (base 0) of the found option.
# The script will exit if the value was not extracted or is invalid.
#

handles_json_arg() {

    local json_file="$1"
    local json_arg="$2"
    shift 2
    local options=("$@")
    local value
    local index=0

    # Ensure jq is installed
    if ! command -v jq &> /dev/null; then
         c_printf RED "Error: " DEFAULT "'jq' is not installed, try 'sudo dnf install jq'\n" >&2
        exit 1
    fi

    # Ensure the JSON file exists and is readable
    if [[ ! -r "$json_file" ]]; then
         c_printf RED "Error: " DEFAULT "'$json_file' does not exist or is not readable.\n" >&2
        exit 1
    fi

    # Extract the argument from the JSON
    value=$(jq -r --arg arg "$json_arg" '.[$arg]' "$json_file")

    if [[ -z "$value" || "$value" == "null" ]]; then
        c_printf RED "Error: " DEFAULT "'$json_arg' not found or invalid in '$json_file'.\n" >&2
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
    c_printf RED "Error: " DEFAULT "'$json_arg' value in '$json_file'. Expected one of ${options[*]}, but found '$value'.\n" >&2
    exit 1
}

##
# @brief Read parameters from an external JSON file.
# @param JSON file name.
# @return None. The function exits with status 1 on error.
# @note prerequisite: JSON parser 'sudo dnf install jq -y'
#

handle_arguments_json() {

    local json_file="$1"
    local value

    # Check if the JSON file exists
    if [[ ! -f "$json_file" ]]; then
         c_printf RED "Error: " DEFAULT "JSON file '$json_file' not found.\n"
         exit 1
    fi

    # Validate JSON format
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        c_printf RED "Error: " DEFAULT "Invalid JSON format in '$json_file'.\n"
        exit 1
    fi

    # Store the JSON file globally for later.
    json_file_name=$json_file 

    # Extract the arguments from the JSON

    value=$(jq -r '.app_source_path' "$json_file")
    application_source_path=$(eval echo "$value") # Expand since this is a path.

    value=$(jq -r '.cmake_template_file' "$json_file")
    toolchain_template_file=$(eval echo "$value") # Expand since this a path.
   
    # Build target could be either "Simics" or "Veloce" so:
    handles_json_arg $json_file "build_target" "Simics" "Veloce"
    if [[ $? -eq 0 ]]; then
         script_args=$((script_args | BUILD_OPT_SIMICS))
    else
         script_args=$((script_args | BUILD_OPT_VELOCE))
    fi

    # Build type could be either "Debug" or "Release" so:
    handles_json_arg $json_file "build_type" "Debug" "Release"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_DEBUG))
    else
        script_args=$((script_args | BUILD_OPT_RELEASE))
    fi

    # Boolean : Script chatty - dump everything to the terminal
    handles_json_arg $json_file "script_chatty" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_SCRIPT_CHATTY))
    fi

    # Boolean : Script show debug - allow for debug log messages
    handles_json_arg $json_file "script_show_debug" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_SCRIPT_SHOW_DEBUG))
    fi

    # Boolean : Clean Zephyr using 'make clean'
    handles_json_arg $json_file "clean_zephyr" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_MAKE_CLEAN))
    fi

    # Boolean : Clean logs between builds
    handles_json_arg $json_file "clear_logs" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_CLEAR_LOGS))
    fi

    # Boolean : Fast re-build Zephyr using 'make' and exit:
    handles_json_arg $json_file "make_zephyr_only" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_FAST_MAKE))
    fi
}

##
# @brief Print script usage help.
# @param Script name ($0)
#

print_usage() {

    c_printf YELLOW "Usage: $(basename $0) [" \
        PURPLE "'App source path'" DEFAULT " or " \
        CYAN "'JSON file name']" DEFAULT " [options...]\n"

    c_printf "Options:\n"
    c_printf YELLOW "\t-s  " DEFAULT " Build for Simics.\n"
    c_printf YELLOW "\t-v  " DEFAULT " Build for Veloce.\n"
    c_printf YELLOW "\t-d  " DEFAULT " Build debug version.\n"
    c_printf YELLOW "\t-r  " DEFAULT " Build Release version.\n"
    c_printf YELLOW "\t-f  " DEFAULT " Drop Zephyr compilation leftovers.\n"
    c_printf YELLOW "\t-c  " DEFAULT " Clean artifacts between builds.\n"
    c_printf YELLOW "\t-m  " DEFAULT " Fast clean & make Simics.\n"
    c_printf YELLOW "\t-t  " DEFAULT " Output everything to terminal.\n"
    c_printf YELLOW "\t-j  " DEFAULT " Use the specified JSON for arguments.\n"
    c_printf "\n"
}

##
# @brief Handle command-line arguments for the build script.
# @details This function processes the command-line arguments provided to the
#          build script, setting appropriate build flags and validating inputs.
# @param application_source_path The application source directory path.
# @param script_args A bitmask of build options.
# @return None. The function exits with status 1 on error.
# @usage handle_arguments <app_source_path> [options...]
##

handle_arguments() {

    local numeric_val=0
    printf "\n"

    if [[ $# -lt 1 ]]; then
        c_printf RED "Error: " DEFAULT "No app source path provided.\n"
        exit 1
    fi

    # Check if the first argument requires to print the script usage.
    if [[ "$1" == "-?" || "$1" == "--help" || "$1" == "-h" ]]; then
        print_usage $0
        exit 0
    fi

    # Read the first argument into the 'application_source_path' global.
    # This could be the JSON file path as well, in which case it will be set
    # later in handle_arguments_json()

    application_source_path="$1"
    shift  # Remove the first argument

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|"-?"|--?)
                print_usage $0
                exit 0
                ;;
            -j|--json)
                handle_arguments_json $application_source_path
                break
                ;;
            -s|--simics)
                script_args=$((script_args | BUILD_OPT_SIMICS))
                ;;
            -v|--veloce)
                script_args=$((script_args | BUILD_OPT_VELOCE))
                ;;
            -d|--debug)
                script_args=$((script_args | BUILD_OPT_DEBUG))
                ;;
            -r|--release)
                script_args=$((script_args | BUILD_OPT_RELEASE))
                ;;
            -c|--clean)
                script_args=$((script_args | BUILD_OPT_MAKE_CLEAN))
                ;;
            -f|--fresh)
                script_args=$((script_args | BUILD_OPT_START_FRESH))
                ;;
            -m|--make)
                script_args=$((script_args | BUILD_OPT_FAST_MAKE))
                ;;
            -t|--terminal)
                script_args=$((script_args | BUILD_OPT_SCRIPT_CHATTY))
                ;;
            -l|--loud)
                script_args=$((script_args | BUILD_OPT_SCRIPT_SHOW_DEBUG))
                ;;
            --) # End of all options
                shift
                break
                ;;
            -*)
                c_printf RED "Error: " DEFAULT "Unsupported flag " CYAN "$1.\n" >&2
                exit 1
                ;;
        esac
        shift
    done
    
    # User inputs logic validation.
    if [[ ! -e "$application_source_path" ]]; then
        c_printf RED "Error: " DEFAULT "Invalid app source path: '$application_source_path'.\n"
        exit 1
    fi

    # Normalize tool chain template file name.
    toolchain_template_file=$(to_absolute_path "$toolchain_template_file")

    if [[ ! -e "$toolchain_template_file" ]]; then
        c_printf RED "Error: " DEFAULT "Invalid template file path: '$toolchain_template_file'.\n"
        exit 1
    fi

    bit_mask=$((BUILD_OPT_SIMICS | BUILD_OPT_VELOCE))
    if (( (script_args & bit_mask) == bit_mask )); then
         c_printf RED "Error: " DEFAULT "Please select either Simics (-s) or Veloce (-v)."
        exit 1
    fi

    bit_mask=$((BUILD_OPT_DEBUG | BUILD_OPT_RELEASE))
    if (( (script_args & bit_mask) == bit_mask )); then
        c_printf RED "Error: " DEFAULT "Please select either release (-r) or debug (-d)."
        exit 1
    fi

    # Target platform:
    if (( (script_args & BUILD_OPT_SIMICS) != 0 )); then
        build_platform="simics"
    else
        build_platform="veloce"
    fi

    # Build profile:
    if (( (script_args & BUILD_OPT_DEBUG) != 0 )); then
        numeric_val=1
        build_type="debug"
    else
        build_type="release"
    fi

    # Normalize export config scrip name
    export_config_script_name=$(to_absolute_path "$export_config_script_name")

    # Export few essential variables
    export BUILD_TYPE=${numeric_val}
    export PLATFORM=${build_platform}
}

##
# @brief Generate a CMake tool-chain file for cross-compilation by substituting
#        values in a template file.
# @details This function generates a CMake tool-chain file for cross-compilation
#           by replacing placeholders in a template file with actual values.
# @param template_path The path to the template tool-chain file.
# @return 0 on success.
#         1 if the wrong number of arguments is provided.
#         2 if the template file is not found.
#         3 if required environment variables are unset
#         4 if the 'sed' command fails.
##

cmake_generate_toolchain_file() {

    if [[ $# -ne 1 ]]; then
      # @usage cmake_generate_toolchain_file <build_path> <template_path>
      return 1
    fi

    local template_path=$1
    local toolchain_file="${build_path}/$toolchain_cmake_file"

    if [[ ! -f "$template_path" ]]; then
      # @note Template file not found at ${template_path}
      return 2
    fi

    # Ensure that required environment variables are set.
    if [[ -z "$build_path" || -z "$SDKTARGETSYSROOT" || -z "$CFLAGS" || -z "$LDFLAGS" ]]; then
      # @note One or more required environment variables are unset.
      return 3
    fi

    # Not cross compiling
    CMAKE_CROSS_COMPILER="set( CMAKE_CROSSCOMPILING FALSE )"

    if (( (script_args & BUILD_OPT_DEBUG) != 0 )); then
      CMAKE_BUILD_TYPE="Debug"
      C_FLAGS_DEBUG="-g -O0"
      CXX_FLAGS_DEBUG="-g -O0"
    else
      CMAKE_BUILD_TYPE="Release"
      C_FLAGS_DEBUG="" # Set appropriately for release
      CXX_FLAGS_DEBUG="" # Set appropriately for release
    fi

    # Use 'sed' to substitute variables correctly handling slashes and avoiding
    # unwanted backslashes.

    sed -e "s|\\\${SDKTARGETSYSROOT}|${SDKTARGETSYSROOT//\//\\/}|g" \
        -e "s|\\\${CROSS_DIR}|${CROSS_DIR//\//\\/}|g" \
        -e "s|\\\${CFLAGS}|${CFLAGS//\//\\/}|g" \
        -e "s|\\\${CXXFLAGS}|${CXXFLAGS//\//\\/}|g" \
        -e "s|\\\${LDFLAGS}|${LDFLAGS//\//\\/}|g" \
        -e "s|\\\${EXTERNAL_TOOLCHAIN}|${EXTERNAL_TOOLCHAIN//\//\\/}|g" \
        -e "s|\\\${CMAKE_CROSS_COMPILER}|${CMAKE_CROSS_COMPILER//\//\\/}|g" \
        -e "s|\\\${build_path}|${build_path//\//\\/}|g" \
        -e "s|\\\${CMAKE_BUILD_TYPE}|${CMAKE_BUILD_TYPE}|g" \
        -e "s|\\\${C_FLAGS_DEBUG}|${C_FLAGS_DEBUG//\//\\/}|g" \
        -e "s|\\\${CXX_FLAGS_DEBUG}|${CXX_FLAGS_DEBUG//\//\\/}|g" \
        "$template_path" > "$toolchain_file"

    if [[ $? -ne 0 ]]; then
      # @note 'sed' could not create the CMake file based on the template
      return 4
    fi

    return 0
}

##
# @brief Configure CMake for the build environment.
# @details This function sets up the CMake build environment using a specified
#          tool-chain file and various configuration options.
# @return The status of the CMake command execution.
#
#

configure_cmake() {

    local path_to_cc
    local oecmake_sitefile

    path_to_cc=$(which ${CROSS_COMPILE}gcc | sed 's:gcc::')
    oecmake_sitefile=

    cd ${build_path}

    # Give the host tools precedence before the SDK host sysroot
    cmake \
        --log-level=ERROR \
        -G 'Unix Makefiles' \
        -DCMAKE_MAKE_PROGRAM=make \
        ${oecmake_sitefile} \
        ${application_source_path} \
        -DLIB_SUFFIX= \
        -DCMAKE_INSTALL_SO_NO_EXE=0 \
        -DCMAKE_TOOLCHAIN_FILE=${build_path}/${toolchain_cmake_file} \
        -DCMAKE_NO_SYSTEM_FROM_IMPORTED=1 \
        -DZEPHYR_BASE=${ZEPHYR_BASE} \
        -DZEPHYR_GCC_VARIANT=yocto \
        -DBOARD=imc_${PLATFORM} \
        -DARCH=arm64 \
        -DCROSS_COMPILE=${path_to_cc} \
        -DZEPHYR_SYSROOT=${SDKTARGETSYSROOT} \
        -DZEPHYR_TOOLCHAIN_VARIANT=yocto \
        -Wno-dev

    # Return the status of the CMake command
    return $?
}

##
#
# @brief Auto- inject the compiled Zephyr binary into a pr-existing NVM file.
# @return 0|1 generic return values.
#

nvm_auto_inject() {

    local value
    local nvm_image_path

    # Exit if the JSON file name is unknown.
    if [ -z "$json_file_name" ]; then
        return 0 # Not using JSON, this firewater is not supported.
    fi

    # Boolean : are we set to inject our binary into the NVM?
    handles_json_arg $json_file_name "nvm_auto_inject" "true" "false"
    if [[ $? -eq 1 ]]; then
        return 0 # Auto inject is not enabled
    fi

    # Get the NVM file names from the JSON file.
    value=$(jq -r '.source_nvm_file_name' "$json_file_name")
    source_nvm_file_name=$(eval echo "$value") # Expand since this is a path.

    value=$(jq -r '.destination_nvm_file_name' "$json_file_name")
    destination_nvm_file_name=$(eval echo "$value") # Expand since this is a path.

    # Basic sanity
    if [ -z "$source_nvm_file_name" -a -z "$destination_nvm_file_name" ]; then
        c_printf RED "Error: " DEFAULT "Invalid source / destination NVM path.\n"
        return $?
    fi

    # Fire inject step and return error if we had any.
    execute_step 11 || { return $?; }    # # 11: Call inject
    
    # Log the location of the new NVM file (absolute) 
    absolute_path=$(to_absolute_path "$destination_nvm_file_name")
    debug_print "New NVM: %s" $absolute_path

    # Perfect!
    return 0
}

##
#
# @brief Build the IMC app project.
# @details This function builds the project by:
#          - Setting up the tool-chain.
#          - Configuring the build environment
#          - Batch execution of the relevant steps.
# @return The status of the last executed command.
#

build_imc_app() {

    debug_print "Building: %s/%s" $build_platform $build_type
    debug_print "Template: %s" $toolchain_template_file

    # Check if IMC_KERNEL_DIR is defined
    if [[ -z "${IMC_KERNEL_DIR}" ]]; then
        c_printf RED "Error: IMC_KERNEL_DIR environment variable not defined.\n" \
                 DEFAULT "Make sure to source the environment setup script.\n"
        return 1
    fi

    # Check if SDKTARGETSYSROOT is defined
    if [[ -z "${SDKTARGETSYSROOT}" ]]; then
        c_printf RED "Error: MEV-TS dedicated tool-chain is not in use.\n" \
                 DEFAULT "Make sure to source the tool-chain environment setup script.\n"
        return 1
    fi

    # Required by child / other dependent scripts.
    export ZEPHYR_BASE=${IMC_KERNEL_DIR}

    # Construct the output build directory based on the selected platform and build type.
    build_path="${IMC_KERNEL_DIR}/build_$(basename ${application_source_path})_${build_platform}_${build_type}"
    
    # Adjust fer global variables to point to the now constructed target build path.
    log_files_path="${build_path}/$log_files_path"
    compiled_binary_name="${build_path}/zephyr/$compiled_binary_name"
    debug_print "Build path: %s" $build_path 

    mkdir -p ${build_path} > /dev/null 2>&1 # Optimistic create the build path.
    if [[ ! -d "${build_path}" ]]; then
         c_printf RED "Error: " DEFAULT "'build_path' does not appear to be a valid path.\n"
        return 1
    fi
    
    # Delete and re-create logs directory.
    if (( (script_args & BUILD_OPT_CLEAR_LOGS) != 0 )); then
        debug_print "Purging build path"
        rm -rf ${log_files_path} > /dev/null 2>&1
        mkdir -p ${log_files_path} > /dev/null 2>&1
    fi

    # If this is just a quick build based an exiting Makefile we can
    # do it right away end exit.
    if (( (script_args & BUILD_OPT_FAST_MAKE) != 0 )); then
        cd ${build_path}

        # Cal clean as needed
        if (( (script_args & BUILD_OPT_MAKE_CLEAN) != 0 )); then
            execute_step 8 || { return $?; }    # 8: Execute 'make clean'
            rm $compiled_binary_name > /dev/null 2>&1
        fi

        execute_step 3  || { return $?; }    # 3:  Quick Zephyr build using 'make'
        execute_step 10 || { return $?; }    # 10: Quick link Zephyr
        return $?
    fi

    # Generate FT ID unless we're set to skip it
    if (( (script_args & BUILD_OPT_SKIP_FT_GENERATION) == 0 )); then
        execute_step 4 || { return $?; }   # 4: Generating ID
    fi

    # Check if the 'start fresh' bit is set, if so, silently attempt to
    # recreate the build directory.
    if (( (script_args & BUILD_OPT_START_FRESH) != 0 )); then

        rm -rf ${build_path} > /dev/null 2>&1
        mkdir -p ${build_path} > /dev/null 2>&1
    fi

    # Execute the step associated with CMake tool chain preparation.
    execute_step 0 || { return $?; }   # 0: Export kernel build configuration
    execute_step 1 || { return $?; }   # 1: Generate CMake tool-chain file
    execute_step 2 || { return $?; }   # 2: Configure CMake

    # Export BUILD_ROOT environment variable
    export BUILD_ROOT="${build_path}"

    # Execute the step associated with the compilation.
    # Each of the sub-projects has it's own step
    execute_step 5 || { return $?; }    # 5: Building MEV Infra lib
    execute_step 6 || { return $?; }    # 6: Building MEV-TS lib
    execute_step 7 || { return $?; }    # 7: Building Infra Common lib

    cd ${build_path}

    # Call 'make clean' if required
    if (( (script_args & BUILD_OPT_MAKE_CLEAN) != 0 )); then
        execute_step 8 || { return $?; }    # 8: Cleaning Zephyr
    fi

    # Lastly, build the Zephyr kernel.
    execute_step 9 || { return $?; }    # 9: Building Zephyr

    return $?  # Return last status code
}

##
# @brief Script entry point.
# @details This function serves as the main entry point of the script. It handles
#          argument processing, environment variable checks, and orchestrates
#          the build process.
# @param "$@" Command-line arguments passed to the script.
# @return The status code of the build process or any preceding failures.
#

main() {

    # Store the current directory
    script_base_path=$(pwd)
    
    # Capture the start time
    start_time=$(date +%s)

    # Parse user arguments, exit on error
    handle_arguments "$@"
    if [ $? -ne 0 ]; then
        c_printf RED "Error: " DEFAULT "Failed to handle arguments.\n"
        return 1
    fi

    # Greetings
    clear
    c_printf "\nIMC Application builder (version " CYAN "$script_version)\n"
    c_printf "-------------------------------------\n"

    # Build and capture the return value.
    build_imc_app
    ret_val=$?

    cd "$script_base_path" # Return to the base path

    # Perform auto inject if the JSON file allows that.
    # Note: no error will be return if this option id disabled.
    if [ $ret_val -eq 0 ]; then
        nvm_auto_inject ;ret_val=$?
    fi

    # Calculate and print operation duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    c_printf "\n\nTook: $duration seconds.\n"

    # If we had an error, print the last few lines of the last log file
    if [ $ret_val -ne 0 ]; then
        c_printf RED "Error: " DEFAULT "IMC application compilation did not complete.\n"
        debug_print "Log: %s" $last_log_file
        
        # Print the log file.
        c_printf "Showing last few lines of: " YELLOW "$(basename "$last_log_file")" DEFAULT ":\n\n"
        # Get the last n lines of the file
        log_text=$(tail -12 "$last_log_file")
        text_print_char_n_times "-" 80 # Separator
        text_print_wrapped "$log_text" 80
        text_print_char_n_times "-" 80 # Separator
    else
        # Great success! Print binary size
        c_printf "IMC application compilation completed " GREEN "successfully.\n"
        c_printf "Size of $(basename "$compiled_binary_name"): " GREEN "$(text_print_file_size "$compiled_binary_name")" DEFAULT "\n"
    fi

    printf "\n"
    return $ret_val
}

##
#
# @brief Invoke the main function with command-line arguments.
# @return The exit status of the main function.
#

main "$@"
exit $?
