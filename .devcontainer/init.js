#!/usr/bin/env node

/**
 * Cross-platform devcontainer initialization script
 * Detects the operating system and runs the appropriate initialization script
 */

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

function isWindows() {
    return process.platform === 'win32';
}

function runCommand(command, options = {}) {
    try {
        console.log(`Running: ${command}`);
        execSync(command, {
            stdio: 'inherit',
            ...options
        });
        return true;
    } catch (error) {
        console.error(`Failed to run command: ${command}`);
        console.error(error.message);
        return false;
    }
}

function main() {
    const scriptDir = __dirname;
    const workspaceRoot = path.dirname(scriptDir);

    // Change to workspace root
    process.chdir(workspaceRoot);

    if (isWindows()) {
        console.log('Detected Windows environment');
        const psScript = path.join(scriptDir, 'init.ps1');

        // Check if PowerShell script exists
        if (!fs.existsSync(psScript)) {
            console.error(`PowerShell script not found: ${psScript}`);
            process.exit(1);
        }

        // Run PowerShell script with appropriate execution policy
        const command = `powershell.exe -NoProfile -ExecutionPolicy Bypass ` +
          `-File "${psScript}"`;
        if (!runCommand(command)) {
            process.exit(1);
        }
    } else {
        console.log('Detected Unix/Linux environment');
        const shScript = path.join(scriptDir, 'init.sh');

        // Check if shell script exists
        if (!fs.existsSync(shScript)) {
            console.error(`Shell script not found: ${shScript}`);
            process.exit(1);
        }

        // Make sure script is executable
        try {
            fs.chmodSync(shScript, '755');
        } catch (error) {
            console.warn('Could not set execute permission on init.sh:',
              error.message);
        }

        // Run shell script
        if (!runCommand(shScript)) {
            process.exit(1);
        }
    }

    console.log('Initialization completed successfully');
}

// Run main function
main();

