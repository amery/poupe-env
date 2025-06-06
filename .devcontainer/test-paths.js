#!/usr/bin/env node

/**
 * Test script to verify path handling on different platforms
 */

const path = require('path');
const os = require('os');

console.log('Platform Information:');
console.log('====================');
console.log(`Platform: ${process.platform}`);
console.log(`OS Type: ${os.type()}`);
console.log(`Home Directory: ${os.homedir()}`);
console.log(`Current Directory: ${process.cwd()}`);

console.log('\nEnvironment Variables:');
console.log('=====================');
console.log(`HOME: ${process.env.HOME || 'not set'}`);
console.log(`USERPROFILE: ${process.env.USERPROFILE || 'not set'}`);
console.log(`USERNAME: ${process.env.USERNAME || 'not set'}`);
console.log(`USER: ${process.env.USER || 'not set'}`);

console.log('\nPath Tests:');
console.log('===========');

// Test path normalization
const testPaths = [
    'C:\\Users\\test\\project',
    '/home/user/project',
    '.docker-run-cache\\home\\user',
    '.docker-run-cache/home/user'
];

testPaths.forEach(testPath => {
    console.log(`\nOriginal: ${testPath}`);
    console.log(`Normalized: ${path.normalize(testPath)}`);
    console.log(`POSIX: ${testPath.replace(/\\/g, '/')}`);
});

// Test workspace folder variable resolution
console.log('\nVSCode Variable Examples:');
console.log('========================');
const workspaceFolder = process.cwd();
const homeDir = os.homedir();

console.log(`${`$\{localWorkspaceFolder\}`} would resolve to: ${workspaceFolder}`);
console.log(`${`$\{localEnv:HOME\}`} would resolve to: ${process.env.HOME || 'undefined on Windows'}`);
console.log(`${`$\{localEnv:USERPROFILE\}`} would resolve to: ${process.env.USERPROFILE || 'undefined on Unix'}`);

// Docker mount path examples
console.log('\nDocker Mount Path Examples:');
console.log('==========================');
const cacheDir = '.docker-run-cache';

if (process.platform === 'win32') {
    console.log(`Windows mount source: ${path.join(workspaceFolder, cacheDir, homeDir)}`);
    console.log(`Docker mount target: ${homeDir.replace(/\\/g, '/').replace(/^([A-Z]):/, '/$1')}`);
} else {
    console.log(`Unix mount source: ${path.join(workspaceFolder, cacheDir, homeDir)}`);
    console.log(`Docker mount target: ${homeDir}`);
}
