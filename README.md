# Build script sample code.

## Modified 'mev_imc_build_app.sh' build script.

This repo hold a modified version of the IMC application build script, following are some of guide lines that this script aims to provide.

1. **Steps**: Like most batch files, this shell build script describes several sequential steps. Once completed, the final compiled binary should be ready for deployment or debugging. This script includes a table of steps, each responsible for a different section of the final product binary.
2. **Step-based Log Files**: Instead of cluttering the console with too much information, this approach redirects each step's output to its own log file for later analysis. These files are stored in the output folder under `/logs`, where the file name is constructed using the step ordinal value followed by its description (e.g., `1_my_step.log`). 
3. **Error Handling**: Any error will result in immediate termination of the script, and the last 20 lines of the last log file will be output to the console. 
4. **Warnings Summary**: When a step is completed, the script will summarize and print the number of occurrences of the word "warning" to alert the user that something might not be quite right in that step. 
5. **Efficient Compilation**: The script allows for executing 'make' in the application target folder, utilizing 'make's' ability to detect and compile only the files that require compilation (e.g., new or modified files and any files affected by changes). This approach enables very fast compilation in a few seconds rather than recompiling the entire project.
6. **JSON File**: The script reads its arguments from a JSON file rather than using traditional console arguments. This approach allows for easily and conveniently using many arguments stored in several files, each describing a slightly different build scenario.

## Usage.

Make sure you have the JSON parsing utility:

```
sudo dnf install jq
```

1. Back up the `mev_imc_build_app.sh` script and copy `test.json`, `toolchain_template.cmake`, and the `mev_imc_build_app.sh` script to the target path, currently located at `/home/emichael/mgv_trunk/sources/imc/zephyr`."

2. Edit `test.json` to reflect your specific configuration. 
3. Execute `./mev_imc_build_app.sh test.json -j`

## Notes.

* Full build:

  ![]https://github.com/emichael72/build_script/blob/main/art/fast.png?raw=true

* Setting `make_zephyr_only` to `true` will quickly build only the Zephyr kernel section of the project.

  ![]https://github.com/emichael72/build_script/blob/main/art/fast.png?raw=true

* Setting `nvm_auto_inject` to `true` will automatically generate an NVM using the compiled Zephyr binary.



