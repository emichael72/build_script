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
        "make_zephyr_only"          : false,
        "ai_assisted_error_info"    : true
    }

'

# Have the swissknife with at all times.
source ./toolbox.sh

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
build_platform="" # Caller selected target build platform could be Simics' or 'Veloce'.
build_type="" # Caller selected compilation profile 'Debug' or 'Release'.
json_file_name="" # The JSON file name in the case we're using JSON
source_nvm_file_name="" # The source NVM file (untouched by this script).
destination_nvm_file_name="" # The updated NVM file name we're about to crate using 'inject'
script_base_path="" # Script base execution path 
ai_assisted_error_info=0 # Let the devil assist you
ai_assisted_timeout=10 # Timeout (seconds) for the OpanAI query.
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
# @brief Print script usage help.
# @param Script name ($0)
#

print_usage() {

    toolbox_c_printf YELLOW "Usage: $(basename $0) [" \
        PURPLE "'App source path'" DEFAULT " or " \
        CYAN "'JSON file name']" DEFAULT " [options...]\n"

    toolbox_c_printf "Options:\n"
    toolbox_c_printf YELLOW "\t-s  " DEFAULT " Build for Simics.\n"
    toolbox_c_printf YELLOW "\t-v  " DEFAULT " Build for Veloce.\n"
    toolbox_c_printf YELLOW "\t-d  " DEFAULT " Build debug version.\n"
    toolbox_c_printf YELLOW "\t-r  " DEFAULT " Build Release version.\n"
    toolbox_c_printf YELLOW "\t-f  " DEFAULT " Drop Zephyr compilation leftovers.\n"
    toolbox_c_printf YELLOW "\t-c  " DEFAULT " Clean artifacts between builds.\n"
    toolbox_c_printf YELLOW "\t-m  " DEFAULT " Fast clean & make Simics.\n"
    toolbox_c_printf YELLOW "\t-t  " DEFAULT " Output everything to terminal.\n"
    toolbox_c_printf YELLOW "\t-j  " DEFAULT " Use the specified JSON for arguments.\n"
    toolbox_c_printf "\n"
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
         toolbox_c_printf RED "Error: " DEFAULT "JSON file '$json_file' not found.\n"
         exit 1
    fi

    # Validate JSON format
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        toolbox_c_printf RED "Error: " DEFAULT "Invalid JSON format in '$json_file'.\n"
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
     toolbox_extract_json_arg $json_file "build_target" "Simics" "Veloce"
    if [[ $? -eq 0 ]]; then
         script_args=$((script_args | BUILD_OPT_SIMICS))
    else
         script_args=$((script_args | BUILD_OPT_VELOCE))
    fi

    # Build type could be either "Debug" or "Release" so:
    toolbox_extract_json_arg $json_file "build_type" "Debug" "Release"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_DEBUG))
    else
        script_args=$((script_args | BUILD_OPT_RELEASE))
    fi

    # Boolean : Script chatty - dump everything to the terminal
    toolbox_extract_json_arg $json_file "script_chatty" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_SCRIPT_CHATTY))
    fi

    # Boolean : Script show debug - allow for debug log messages
    toolbox_extract_json_arg $json_file "script_show_debug" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_SCRIPT_SHOW_DEBUG))
    fi

    # Boolean : Clean Zephyr using 'make clean'
    toolbox_extract_json_arg $json_file "clean_zephyr" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_MAKE_CLEAN))
    fi

    # Boolean : Clean logs between builds
    toolbox_extract_json_arg $json_file "clear_logs" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_CLEAR_LOGS))
    fi

    # Boolean : Fast re-build Zephyr using 'make' and exit:
    toolbox_extract_json_arg $json_file "make_zephyr_only" "true" "false"
    if [[ $? -eq 0 ]]; then
        script_args=$((script_args | BUILD_OPT_FAST_MAKE))
    fi

    # Check if AI-assisted error handling is enabled
    toolbox_extract_json_arg $json_file "ai_assisted_error_info" "true" "false"
    if [[ $? -eq 0 ]]; then
        ai_assisted_error_info=1
    fi

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

handle_arguments_console() {

    local numeric_val=0
    local showe_debug=0
    local chatty=0

    printf "\n"

    if [[ $# -lt 1 ]]; then
        toolbox_c_printf RED "Error: " DEFAULT "No app source path provided.\n"
        exit 1
    fi

    # Check if the first argument requires to print the script usage.
    if [[ "$1" == "-?" || "$1" == "--help" || "$1" == "-h" ]]; then
        print_usage $0
        exit 0
    fi

    # Read the first argument into the 'application_source_path' global.
    # This could be the JSON file path as well, in which case it will be set
    # later in json()

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
                toolbox_c_printf RED "Error: " DEFAULT "Unsupported flag " CYAN "$1.\n" >&2
                exit 1
                ;;
        esac
        shift
    done
    
    # User inputs logic validation.
    if [[ ! -e "$application_source_path" ]]; then
        toolbox_c_printf RED "Error: " DEFAULT "Invalid app source path: '$application_source_path'.\n"
        exit 1
    fi

    # Normalize tool chain template file name.
    toolchain_template_file=$(toolbox_to_absolute_path "$toolchain_template_file")

    if [[ ! -e "$toolchain_template_file" ]]; then
        toolbox_c_printf RED "Error: " DEFAULT "Invalid template file path: '$toolchain_template_file'.\n"
        exit 1
    fi

    bit_mask=$((BUILD_OPT_SIMICS | BUILD_OPT_VELOCE))
    if (( (script_args & bit_mask) == bit_mask )); then
         toolbox_c_printf RED "Error: " DEFAULT "Please select either Simics (-s) or Veloce (-v)."
        exit 1
    fi

    bit_mask=$((BUILD_OPT_DEBUG | BUILD_OPT_RELEASE))
    if (( (script_args & bit_mask) == bit_mask )); then
        toolbox_c_printf RED "Error: " DEFAULT "Please select either release (-r) or debug (-d)."
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
    export_config_script_name=$(toolbox_to_absolute_path "$export_config_script_name")

    # Update the toolbox based on what we got from the caller.
    if (( (script_args & BUILD_OPT_SCRIPT_SHOW_DEBUG) != 0 )); then
        showe_debug=1
    fi

    if (( (script_args & BUILD_OPT_SCRIPT_CHATTY) != 0 )); then
        chatty=1
    fi
    toolbox_set_options $showe_debug $chatty

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
    toolbox_extract_json_arg $json_file_name "nvm_auto_inject" "true" "false"
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
        toolbox_c_printf RED "Error: " DEFAULT "Invalid source / destination NVM path.\n"
        return $?
    fi

    # Fire inject step and return error if we had any.
    toolbox_exec_step steps 11 || { return $?; }    # # 11: Call inject
    
    # Log the location of the new NVM file (absolute) 
    absolute_path=$(toolbox_to_absolute_path "$destination_nvm_file_name")
    toolbox_d_printf "New NVM: %s" $absolute_path

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

    toolbox_d_printf "Building: %s/%s" $build_platform $build_type
    toolbox_d_printf "Template: %s" $toolchain_template_file

    # Check if IMC_KERNEL_DIR is defined
    if [[ -z "${IMC_KERNEL_DIR}" ]]; then
        toolbox_c_printf RED "Error: IMC_KERNEL_DIR environment variable not defined.\n" \
                 DEFAULT "Make sure to source the environment setup script.\n"
        return 1
    fi

    # Check if SDKTARGETSYSROOT is defined
    if [[ -z "${SDKTARGETSYSROOT}" ]]; then
        toolbox_c_printf RED "Error: MEV-TS dedicated tool-chain is not in use.\n" \
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
    toolbox_d_printf "Build path: %s" $build_path 

    mkdir -p ${build_path} > /dev/null 2>&1 # Optimistic create the build path.
    if [[ ! -d "${build_path}" ]]; then
         toolbox_c_printf RED "Error: " DEFAULT "'build_path' does not appear to be a valid path.\n"
        return 1
    fi
    
    # Delete and re-create logs directory.
    if (( (script_args & BUILD_OPT_CLEAR_LOGS) != 0 )); then
        toolbox_d_printf "Purging build path"
        rm -rf ${log_files_path} > /dev/null 2>&1
        mkdir -p ${log_files_path} > /dev/null 2>&1
    fi

    # If this is just a quick build based an exiting Makefile we can
    # do it right away end exit.
    if (( (script_args & BUILD_OPT_FAST_MAKE) != 0 )); then
        cd ${build_path}

        # Cal clean as needed
        if (( (script_args & BUILD_OPT_MAKE_CLEAN) != 0 )); then
            toolbox_exec_step steps 8 || { return $?; }    # 8: Execute 'make clean'
            rm $compiled_binary_name > /dev/null 2>&1
        fi

        toolbox_exec_step steps 3  || { return $?; }    # 3:  Quick Zephyr build using 'make'
        toolbox_exec_step steps 10 || { return $?; }    # 10: Quick link Zephyr
        return $?
    fi

    # Generate FT ID unless we're set to skip it
    if (( (script_args & BUILD_OPT_SKIP_FT_GENERATION) == 0 )); then
        toolbox_exec_step steps 4 || { return $?; }   # 4: Generating ID
    fi

    # Check if the 'start fresh' bit is set, if so, silently attempt to
    # recreate the build directory.
    if (( (script_args & BUILD_OPT_START_FRESH) != 0 )); then

        rm -rf ${build_path} > /dev/null 2>&1
        mkdir -p ${build_path} > /dev/null 2>&1
    fi

    # Execute the step associated with CMake tool chain preparation.
    toolbox_exec_step steps 0 || { return $?; }   # 0: Export kernel build configuration
    toolbox_exec_step steps 1 || { return $?; }   # 1: Generate CMake tool-chain file
    toolbox_exec_step steps 2 || { return $?; }   # 2: Configure CMake

    # Export BUILD_ROOT environment variable
    export BUILD_ROOT="${build_path}"

    # Execute the step associated with the compilation.
    # Each of the sub-projects has it's own step
    toolbox_exec_step steps 5 || { return $?; }    # 5: Building MEV Infra lib
    toolbox_exec_step steps 6 || { return $?; }    # 6: Building MEV-TS lib
    toolbox_exec_step steps 7 || { return $?; }    # 7: Building Infra Common lib

    cd ${build_path}

    # Call 'make clean' if required
    if (( (script_args & BUILD_OPT_MAKE_CLEAN) != 0 )); then
        toolbox_exec_step steps 8 || { return $?; }    # 8: Cleaning Zephyr
    fi

    # Lastly, build the Zephyr kernel.
    toolbox_exec_step steps 9 || { return $?; }    # 9: Building Zephyr

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
    handle_arguments_console "$@"
    if [ $? -ne 0 ]; then
        toolbox_c_printf RED "Error: " DEFAULT "Failed to handle arguments.\n"
        return 1
    fi

    # Greetings
    # clear
    toolbox_c_printf "\nIMC Application builder (version " CYAN "$script_version)\n"
    toolbox_c_printf "-------------------------------------\n"

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
    toolbox_c_printf "\n\nTook: $duration seconds.\n"

    # If we had an error, print the last few lines of the last log file
    if [ $ret_val -ne 0 ]; then
        toolbox_c_printf RED "Error: " DEFAULT "IMC application compilation did not complete.\n"
        toolbox_d_printf "Log: %s" $toolbox_last_log_file
        
        # Print the log file.
        toolbox_c_printf "Showing last few lines of: " YELLOW "$(basename "$toolbox_last_log_file")" DEFAULT ":\n\n"
        # Get the last n lines of the file
        log_text=$(tail -12 "$toolbox_last_log_file")
        toolbox_print_char_n_times "-" 80 # Separator
        toolbox_print_wrapped "$log_text" 80
        toolbox_print_char_n_times "-" 80 # Separator
    else
        # Great success! Print binary size
        toolbox_c_printf "IMC application compilation completed " GREEN "successfully.\n"
        toolbox_c_printf "Size of $(basename "$compiled_binary_name"): " GREEN "$(toolbox_print_file_size "$compiled_binary_name")" DEFAULT "\n"
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
