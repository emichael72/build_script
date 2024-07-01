
"""
imc_steps_manager.py

This script manages and validates build steps defined in a JSON file.

Functions:
- validate_steps(json_file): Validates the JSON file structure for build steps.
- get_step_element(json_file, step_index, element_name): Retrieves the value of 
  a specific element for a given step index.
- step_verify_work_path(json_file, step_index): Verifies that the work path for 
  a given step index is a valid accessible path.
- step_verify_command(json_file, step_index): Verifies that the execute command 
  for a given step index is a valid executable in the system path.
- step_get_count(json_file): Retrieves the count of steps, returning 0 in case of error.

Usage examples from Bash:
- Validate steps: 
  python resources/imc_steps_manager.py "validate_steps('resources/imc_build_steps.json')"
- Get step element: 
  python resources/imc_steps_manager.py "get_step_element('resources/imc_build_steps.json', 1, 'description')"
- Verify work path: 
  python resources/imc_steps_manager.py "step_verify_work_path('resources/imc_build_steps.json', 1)"
- Verify command: 
  python resources/imc_steps_manager.py "step_verify_command('resources/imc_build_steps.json', 1)"
- Get count of steps: 
  python resources/imc_steps_manager.py "step_get_count('resources/imc_build_steps.json')"
"""

import os
import sys
import json
import re
import subprocess

# Global debug flag
script_debug_enabled = False

def validate_steps(json_file):
    """
    Validate the JSON file structure for build steps.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.

    Returns:
    int: 0 if validation passes, 1 otherwise.
    """
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        if 'imc_build_steps' not in data:
            if script_debug_enabled:
                print("Root branch is not 'imc_build_steps'")
            return 1
        
        steps = data['imc_build_steps']
        indexes = set()

        for step in steps:
            if 'index' not in step or 'description' not in step or 'work_path' not in step or 'execute_command' not in step:
                if script_debug_enabled:
                    print("Each step must have 'index', 'description', 'work_path', and 'execute_command'")
                return 1

            if step['index'] in indexes:
                if script_debug_enabled:
                    print("Duplicate index found: {}".format(step['index']))
                return 1
            indexes.add(step['index'])

            if not isinstance(step['break_on_error'], bool) or not isinstance(step['force_verbose'], bool):
                if script_debug_enabled:
                    print("Boolean elements must be either true or false")
                return 1

            if not isinstance(step['index'], int):
                if script_debug_enabled:
                    print("Index must be a decimal")
                return 1

        return 0
    except Exception as e:
        if script_debug_enabled:
            print("Error in validate_steps: {}".format(str(e)))
        return 1


def step_get_count(json_file):
    """
    Retrieve the count of steps.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.

    Returns:
    int: Number of steps, or 1 in case of error.
    """
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        if 'imc_build_steps' in data:
            return len(data['imc_build_steps'])
        return 1
    except Exception as e:
        if script_debug_enabled:
            print("Error in step_get_count: {}".format(str(e)))
        return 1

def get_step_element(json_file, step_index, element_name):
    """
    Retrieve the value of a specific element for a given step index.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.
    step_index (int): Index of the step.
    element_name (str): Name of the element to retrieve.

    Returns:
    str: Value of the specified element, fully expanded if it contains environment variables.
         Returns an empty string and 1 if any required environment variable is not set.
    """
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)

        steps = data['imc_build_steps']
        for step in steps:
            if step['index'] == step_index:
                element_value = step.get(element_name, "")
                if element_value == "":
                    return ""
                if element_value:
                    parts = element_value.split(" ")
                    expanded_parts = []
                    for part in parts:
                        while "${" in part and "}" in part:
                            start_index = part.find("${")
                            end_index = part.find("}", start_index) + 1
                            env_var = part[start_index + 2:end_index - 1]
                            env_value = os.environ.get(env_var, None)
                            if env_value is None:
                                if script_debug_enabled:
                                    print("Error: Environment variable '{}' is not set".format(env_var))
                                return "1"
                            part = part.replace("${" + env_var + "}", env_value)
                        expanded_parts.append(part)
                    return " ".join(expanded_parts)
        return 1
    except Exception as e:
        if script_debug_enabled:
            print("Error in get_step_element while getting step " + str(step_index) + ": {}".format(str(e)))
        return 1


def step_verify_work_path(json_file, step_index):
    """
    Verify that the work path for a given step index is a valid accessible path.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.
    step_index (int): Index of the step.

    Returns:
    int: 0 if the work path is valid, 1 otherwise.
    """
    try:
        work_path = get_step_element(json_file, step_index, 'work_path')
        if work_path and os.path.isdir(work_path):
            return 0
        return 1
    except Exception as e:
        if script_debug_enabled:
            print("Error in step_verify_work_path: {}".format(str(e)))
        return 1

def step_get_formatted_description(json_file, step_index):
    """
    Retrieve a step description, formatted for safe file naming:
    1. Convert to lower case.
    2. Replace spaces with underscores.
    3. Remove any character that may create an issue when the resulting string is used to create a file.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.
    step_index (int): Index of the step.

    Returns:
    str: Formatted step description, or 1 in case of error.
    """
    try:
        description = get_step_element(json_file, step_index, 'description')
        if description:
            formatted_description = description.lower()
            formatted_description = formatted_description.replace(" ", "_")
            formatted_description = re.sub(r'[^a-z0-9_]', '', formatted_description)
            return formatted_description
        return 1
    except Exception as e:
        if script_debug_enabled:
            print("Error in step_get_formatted_description: {}".format(str(e)))
        return 1

def step_verify_command(json_file, step_index):
    """
    Verify that the execute command for a given step index is a valid executable in the system path.

    Parameters:
    json_file (str): Path to the JSON file containing the steps.
    step_index (int): Index of the step.

    Returns:
    int: 0 if the execute command is valid, 1 otherwise.
    """
    try:
        command = get_step_element(json_file, step_index, 'execute_command')
        if command and subprocess.call(["which", command], stdout=subprocess.PIPE, stderr=subprocess.PIPE) == 0:
            return 0
        return 1
    except Exception as e:
        if script_debug_enabled:
            print("Error in step_verify_command: {}".format(str(e)))
        return 1

def main():
    if len(sys.argv) != 2:
        print("Usage: python steps_manager.py \"<function_name>(<args>)\"")
        sys.exit(1)
    
    command = sys.argv[1]

    try:
        result = eval(command)
        if result is not None:
            print(result)
        sys.exit(result if isinstance(result, int) else 1)
    except Exception as e:
        if script_debug_enabled:
            print("Error: {}".format(str(e)))
        sys.exit(1)

if __name__ == "__main__":
    main()
