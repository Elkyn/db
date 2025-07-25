#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

const GITHUB_REPO = 'Elkyn/db';
const packageJson = require('./package.json');
const RELEASE_TAG = process.env.ELKYN_VERSION || `v${packageJson.version}`;

const platform = process.platform;
const arch = process.arch;

console.log(`Installing @elkyn/store for ${platform} ${arch}...`);

// Map platform/arch to binary name in GitHub release
const binaryMap = {
  'darwin-arm64': 'elkyn_store-darwin-arm64.node',
  'darwin-x64': 'elkyn_store-darwin-x64.node',
  'linux-x64': 'elkyn_store-linux-x64.node',
  'linux-arm64': 'elkyn_store-linux-arm64.node',
  'win32-x64': 'elkyn_store-win32-x64.node'
};

const binaryName = binaryMap[`${platform}-${arch}`];

async function downloadBinary(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, { headers: { 'User-Agent': 'elkyn-store-installer' } }, (response) => {
      if (response.statusCode === 302 || response.statusCode === 301) {
        // Follow redirect
        downloadBinary(response.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      
      if (response.statusCode !== 200) {
        reject(new Error(`Failed to download: ${response.statusCode}`));
        return;
      }
      
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve();
      });
    }).on('error', reject);
  });
}

async function getLatestReleaseInfo() {
  return new Promise((resolve, reject) => {
    const url = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;
    https.get(url, {
      headers: {
        'User-Agent': 'elkyn-store-installer',
        'Accept': 'application/vnd.github.v3+json'
      }
    }, (response) => {
      let data = '';
      response.on('data', chunk => data += chunk);
      response.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function getReleaseInfo(tag) {
  if (tag === 'latest') {
    return getLatestReleaseInfo();
  }
  
  return new Promise((resolve, reject) => {
    const url = `https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${tag}`;
    https.get(url, {
      headers: {
        'User-Agent': 'elkyn-store-installer',
        'Accept': 'application/vnd.github.v3+json'
      }
    }, (response) => {
      let data = '';
      response.on('data', chunk => data += chunk);
      response.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function installFromGitHub() {
  if (!binaryName) {
    console.log('No pre-built binary available for your platform.');
    return false;
  }

  try {
    console.log(`Fetching release info for ${RELEASE_TAG}...`);
    const release = await getReleaseInfo(RELEASE_TAG);
    
    if (!release || !release.assets) {
      console.log('No release found');
      return false;
    }
    
    const asset = release.assets.find(a => a.name === binaryName);
    if (!asset) {
      console.log(`Binary ${binaryName} not found in release`);
      return false;
    }
    
    // Create build directory
    const buildDir = path.join(__dirname, 'build', 'Release');
    fs.mkdirSync(buildDir, { recursive: true });
    
    const targetPath = path.join(buildDir, 'elkyn_store.node');
    
    console.log(`Downloading ${binaryName} from GitHub release ${release.tag_name}...`);
    await downloadBinary(asset.browser_download_url, targetPath);
    
    // Make binary executable on Unix
    if (platform !== 'win32') {
      fs.chmodSync(targetPath, 0o755);
    }
    
    console.log(`Successfully installed pre-built binary from GitHub!`);
    return true;
  } catch (error) {
    console.error('Failed to download from GitHub:', error.message);
    return false;
  }
}

async function buildFromSource() {
  console.log('Building from source...');
  
  try {
    // Check if LMDB is available
    if (platform === 'darwin') {
      try {
        execSync('pkg-config --libs lmdb', { stdio: 'ignore' });
      } catch {
        console.error('Error: LMDB not found. Please install it first:');
        console.error('  macOS: brew install lmdb');
        process.exit(1);
      }
    } else if (platform === 'linux') {
      try {
        execSync('pkg-config --libs lmdb', { stdio: 'ignore' });
      } catch {
        console.error('Error: LMDB not found. Please install it first:');
        console.error('  Ubuntu/Debian: sudo apt install liblmdb-dev');
        console.error('  RHEL/CentOS: sudo yum install lmdb-devel');
        process.exit(1);
      }
    }
    
    // Check if static library exists
    const staticLib = path.join(__dirname, '..', 'zig-out', 'lib', 'libelkyn-embedded-static.a');
    if (!fs.existsSync(staticLib)) {
      console.error('Error: Elkyn static library not found.');
      console.error('Please build the project first with: zig build -Doptimize=ReleaseFast');
      process.exit(1);
    }
    
    // Build from source
    execSync('node-gyp rebuild', { stdio: 'inherit' });
    console.log('Successfully built from source!');
  } catch (error) {
    console.error('Failed to build from source:', error.message);
    process.exit(1);
  }
}

// Main installation flow
(async () => {
  // Try to download from GitHub first
  const downloaded = await installFromGitHub();
  
  if (!downloaded) {
    // Fall back to building from source
    await buildFromSource();
  }
  
  // Verify installation
  try {
    const modulePath = path.join(__dirname, 'build', 'Release', 'elkyn_store.node');
    require(modulePath);
    console.log('Installation successful!');
  } catch (error) {
    console.error('Installation verification failed:', error.message);
    process.exit(1);
  }
})();