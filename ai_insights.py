#!/usr/bin/env python3

"""
ai_insights.py

This script uses the OpenAI API to provide insights and potential fixes for errors 
based on provided error messages and file contents. The script requires OpenAI's 
Python library to be installed and an API key to be set as an environment variable.

Usage:
    python ai_insights.py <error_message> <file_content> <timeout>

Requires:
    - Python 3.x
    - openai library (latest version recommended)
    - An OpenAI API key set as an environment variable 'OPENAI_API_KEY'

Note:
    If using a version of the OpenAI library prior to 1.0.0, ensure compatibility 
    with your API usage.

    Prerequisites:
    1.  Downgrade openai:
        python3 -m pip install openai==0.28 
    2.  Install 'Pygments'
        pip3 install Pygments --user
"""

import openai
import sys
import os
import concurrent.futures
import textwrap
import pygments
from pygments import highlight
from pygments.lexers import CLexer
from pygments.formatters import TerminalFormatter

# Ensure the API key is set using an environment variable
openai.api_key = os.getenv('OPENAI_API_KEY')
if not openai.api_key:
    raise ValueError("No OpenAI API key found. Set the OPENAI_API_KEY environment variable.")


def print_chatgpt_insights(error_message, file_content):
    """
    Generates insights based on the provided error message and file content 
    using the OpenAI API.

    Args:
        error_message (str): The error message encountered.
        file_content (str): The content of the file causing the error.

    Returns:
        Count of Insights and potential fixes.
    """

    prompt = f"""
    1. Please provide a concise proposed fix for the function responsible the failure.\n
    2. Focus only on the function that triggered the error.\n
    3. Use up to 300 tokens and wrap your code at 80 columns.\n
    4. Add a fix description, function name if applicable, and the line of code where 
        the fix should be applied, all enclosed in as C multi-line comments.\n
    5. Do not attempt to implement unknown functions.\n
    6. Do not simply comment out an unrecognized error.\n
    7. Base your reply on the GCC error message and content of source file.\n

    GCC error message:
    {error_message}

    Source file content:
    {file_content}
    """

    try:
        response = openai.ChatCompletion.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=300,  # Increase this to get more detailed responses
            n=1,
            stop=None,
            temperature=0.8,
        )
    except openai.error.RateLimitError as e:
        print ("Rate limit exceeded. Please try again later.")
        return 0
    except Exception as e:
        print ( f"An error occurred: {e}")
        return 0

    # Get the total number of responses
    total_responses = len(response['choices'])

    # Process and print each response.
    for i in range(total_responses):
        insight = response['choices'][i]['message']['content'].strip()
        if insight:
             clear_code = format_text(insight)
             if clear_code:
                if total_responses > 1:
                    # Print the  response number when there are a few.
                    print ("/* Fix " + str(i) + ":*/")
                print (get_syntax_highlighted_code(clear_code))

    return total_responses


def get_syntax_highlighted_code(code):
    """
    Prints the given code with syntax highlighting for C language.

    Args:
        code (str): The C code to be highlighted.
    """
    lexer = CLexer()
    formatter = TerminalFormatter()
    highlighted_code = highlight(code, lexer, formatter)
    return highlighted_code


def format_text(text):
    """
    Extracts C code from the text, removes code block markers, and adds 4 spaces 
    before each line If there is no C code in the stream, it returns an empty string.

    Args:
        text (str): The input text containing C code and possibly other content.

    Returns:
        str: The formatted C code or an empty string if no C code is found.
    """
    formatted_text = []
    in_code_block = False

    for line in text.split('\n'):
        if line.strip().startswith("```c"):
            in_code_block = True
        elif line.strip().startswith("```") and in_code_block:
            in_code_block = False
        elif in_code_block:
            formatted_text.append("    " + line)
    
    return '\n'.join(formatted_text)


if __name__ == "__main__":
    """
    Entry point.
    """
    if len(sys.argv) != 4:
        print("Usage: python ai_insights.py <error_message> <file_content> <timeout>")
        sys.exit(1)

    error_message = sys.argv[1]
    file_content = sys.argv[2]
    timeout = int(sys.argv[3])

    with concurrent.futures.ThreadPoolExecutor() as executor:
        future = executor.submit(print_chatgpt_insights, error_message, file_content)
        try:
            insights = future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            print("API request timeout")
            sys.exit(1)

    sys.exit(0)
