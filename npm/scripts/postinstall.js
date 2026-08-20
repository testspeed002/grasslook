#!/usr/bin/env node

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

function main() {
  if (process.platform !== 'darwin') {
    console.warn('⚠️  Grasslook is designed specifically for macOS (Sonoma / Sequoia).');
    return;
  }

  const bundledArchive = path.join(__dirname, '../app/Grasslook.app.tar.gz');
  const targetDir = '/Applications';
  const targetApp = path.join(targetDir, 'Grasslook.app');
  const userFallbackDir = path.join(os.homedir(), '.grasslook');
  const userFallbackApp = path.join(userFallbackDir, 'Grasslook.app');

  if (fs.existsSync(bundledArchive)) {
    try {
      console.log('==> Installing Grasslook into /Applications...');
      if (fs.existsSync(targetApp)) {
        try { execSync(`rm -rf "${targetApp}"`); } catch (_) {}
      }
      execSync(`tar -xzf "${bundledArchive}" -C "${targetDir}"`);
      console.log('🌱 Grasslook installed successfully to /Applications/Grasslook.app');
      return;
    } catch (err) {
      console.log('==> Standard /Applications write failed, installing to ~/.grasslook/ ...');
      if (!fs.existsSync(userFallbackDir)) {
        fs.mkdirSync(userFallbackDir, { recursive: true });
      }
      if (fs.existsSync(userFallbackApp)) {
        try { execSync(`rm -rf "${userFallbackApp}"`); } catch (_) {}
      }
      execSync(`tar -xzf "${bundledArchive}" -C "${userFallbackDir}"`);
      console.log(`🌱 Grasslook installed successfully to ${userFallbackApp}`);
      return;
    }
  } else {
    console.log('ℹ️  Pre-bundled archive not present in npm tarball.');
    console.log('    Grasslook will launch using your locally built or installed application.');
  }
}

main();
