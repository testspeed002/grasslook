#!/usr/bin/env node

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

function findAppPath() {
  const standardPath = '/Applications/Grasslook.app';
  if (fs.existsSync(standardPath)) {
    return standardPath;
  }

  const userPath = path.join(os.homedir(), '.grasslook/Grasslook.app');
  if (fs.existsSync(userPath)) {
    return userPath;
  }

  const localDevRelease = path.join(__dirname, '../../.derivedData/Build/Products/Release/Grasslook.app');
  if (fs.existsSync(localDevRelease)) {
    return localDevRelease;
  }

  const localDevDebug = path.join(__dirname, '../../.derivedData/Build/Products/Debug/Grasslook.app');
  if (fs.existsSync(localDevDebug)) {
    return localDevDebug;
  }

  return null;
}

function getRunningPID() {
  try {
    const output = execSync('pgrep -f "Grasslook.app/Contents/MacOS/Grasslook"', { encoding: 'utf8' }).trim();
    return output.split('\n')[0] || null;
  } catch (_) {
    return null;
  }
}

function printHelp() {
  console.log(`
🌱 Grasslook CLI — Native macOS Eye Rest & Mindful Distraction Delays

Usage:
  grasslook [command]

Commands:
  start (default)   Launch Grasslook in your menu bar
  status            Check if Grasslook is currently active
  stop / quit       Stop the running Grasslook background process
  help              Show this help menu

Examples:
  npx grasslook           # Launch directly via npx
  grasslook status        # Check process status
  grasslook stop          # Quit application
`);
}

function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'start';

  if (command === 'help' || command === '--help' || command === '-h') {
    printHelp();
    return;
  }

  if (command === 'status') {
    const pid = getRunningPID();
    if (pid) {
      console.log(`🌱 Grasslook is ACTIVE (PID: ${pid})`);
    } else {
      console.log('⚪ Grasslook is not currently running.');
    }
    return;
  }

  if (command === 'stop' || command === 'quit') {
    const pid = getRunningPID();
    if (pid) {
      try {
        execSync('killall Grasslook 2>/dev/null || true');
        console.log('🛑 Grasslook stopped successfully.');
      } catch (err) {
        console.error('Error stopping Grasslook:', err.message);
      }
    } else {
      console.log('⚪ Grasslook was not running.');
    }
    return;
  }

  if (command === 'start') {
    let appPath = findAppPath();

    if (!appPath) {
      console.log('==> Grasslook app bundle not found. Running installer...');
      try {
        require('../scripts/postinstall.js');
        appPath = findAppPath();
      } catch (err) {
        console.error('Installation error:', err.message);
      }
    }

    if (!appPath) {
      console.error('❌ Could not locate Grasslook.app. Please build or install Grasslook.');
      process.exit(1);
    }

    const currentPid = getRunningPID();
    if (currentPid) {
      console.log(`🌱 Grasslook is already active (PID: ${currentPid})`);
    } else {
      console.log(`🌱 Launching Grasslook from ${appPath}...`);
      try {
        execSync(`open -a "${appPath}"`);
        console.log('✨ Grasslook started in your menu bar!');
      } catch (err) {
        console.error('Failed to launch Grasslook:', err.message);
      }
    }
    return;
  }

  console.error(`Unknown command: ${command}`);
  printHelp();
  process.exit(1);
}

main();
