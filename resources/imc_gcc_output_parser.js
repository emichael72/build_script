const parser = require('gcc-output-parser');
const fs = require('fs');

// Function to read file content and clean ANSI escape codes
const readFileAndClean = (filePath) => {
    return new Promise((resolve, reject) => {
        fs.readFile(filePath, 'utf8', (err, data) => {
            if (err) {
                return reject(err);
            }

            // Clean ANSI escape codes
            const cleanedData = data
                .replace(/\x1B\[[0-9;]*[a-zA-Z]/g, '')
                .replace(/\x1B\([0-9;]*[a-zA-Z]/g, '')
                .replace(/\x1B\][0-9;]*/g, '')
                .replace(/\x1B[()#][0-9;]*[a-zA-Z]/g, '')
                .replace(/\x1B\][^\x1B]*\x1B\\/g, '')
                .replace(/\x1B[^a-zA-Z]*[a-zA-Z]/g, '');

            resolve(cleanedData);
        });
    });
};

const parseGccOutput = async (filePath) => {
    try {
        const gccOutput = await readFileAndClean(filePath);
        const parsedOutput = parser.parseString(gccOutput);
        console.log(JSON.stringify(parsedOutput, null, 2));
    } catch (error) {
        console.error('Error reading or parsing file:', error);
    }
};


const gccOutputFilePath = process.argv[2];
parseGccOutput(gccOutputFilePath);
