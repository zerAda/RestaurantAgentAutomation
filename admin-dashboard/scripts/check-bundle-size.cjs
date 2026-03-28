'use strict';

/**
 * check-bundle-size.cjs
 *
 * PERF-08 verification: Confirms that React.lazy() code splitting is structurally active.
 * Reads the compiled output in dist/assets/ and checks:
 *   1. chunkCount >= 5 — lazy() produces one chunk per route, so 5+ confirms splitting
 *   2. entryKB <= 30   — the entry bundle (index-*.js) is ≤30 KB (app shell only)
 *
 * Usage: node scripts/check-bundle-size.cjs
 * Optional env: BUNDLE_BASELINE_KB=<number> — prints reduction % vs monolithic baseline
 */

var fs = require('fs');
var path = require('path');

var distDir = path.resolve(__dirname, '../dist/assets');

if (!fs.existsSync(distDir)) {
  console.error('ERROR: dist/assets/ not found. Run "npm run build" first.');
  process.exit(1);
}

var entries = fs.readdirSync(distDir);
var jsFiles = entries.filter(function (f) { return f.endsWith('.js'); });

if (jsFiles.length === 0) {
  console.error('ERROR: No .js files found in dist/assets/. Build may have failed.');
  process.exit(1);
}

// Sort for deterministic output
jsFiles.sort();

var totalBytes = 0;
var entryBytes = 0;
var entryFile = null;

jsFiles.forEach(function (filename) {
  var filePath = path.join(distDir, filename);
  var stat = fs.statSync(filePath);
  var sizeKB = stat.size / 1024;
  totalBytes += stat.size;

  // Entry bundle: matches index-*.js pattern
  if (/^index-/.test(filename) || /^index\.[a-zA-Z0-9]+\.js$/.test(filename)) {
    if (!entryFile || stat.size < entryBytes) {
      entryFile = filename;
      entryBytes = stat.size;
    }
  }

  console.log('  ' + filename + ' — ' + sizeKB.toFixed(2) + ' KB');
});

// Fallback: if no index-*.js, pick the smallest file as the entry
if (!entryFile) {
  var smallest = null;
  var smallestBytes = Infinity;
  jsFiles.forEach(function (filename) {
    var stat = fs.statSync(path.join(distDir, filename));
    if (stat.size < smallestBytes) {
      smallestBytes = stat.size;
      smallest = filename;
    }
  });
  entryFile = smallest;
  entryBytes = smallestBytes;
}

var totalKB = totalBytes / 1024;
var chunkCount = jsFiles.length;
var entryKB = entryBytes / 1024;

console.log('');
console.log('TOTAL_JS_KB: ' + totalKB.toFixed(2));
console.log('CHUNKS: ' + chunkCount);
console.log('ENTRY_FILE: ' + entryFile);
console.log('ENTRY_KB: ' + entryKB.toFixed(2));

// Optional baseline comparison (informational only)
var baselineKB = parseFloat(process.env.BUNDLE_BASELINE_KB || '0');
if (baselineKB > 0) {
  var reduction = ((baselineKB - totalKB) / baselineKB) * 100;
  console.log('REDUCTION: ' + reduction.toFixed(1) + '% vs baseline (' + baselineKB + ' KB)');
}

console.log('');

// PERF-08 acceptance checks
var chunkOk = chunkCount >= 5;
var entryOk = entryKB <= 30;

if (chunkOk && entryOk) {
  console.log('PERF-08: PASS — code splitting active (' + chunkCount + ' chunks, entry ' + entryKB.toFixed(2) + ' KB)');
  process.exit(0);
} else {
  var reasons = [];
  if (!chunkOk) {
    reasons.push('only ' + chunkCount + ' JS chunk(s) found (need >= 5 to confirm lazy() splitting)');
  }
  if (!entryOk) {
    reasons.push('entry bundle is ' + entryKB.toFixed(2) + ' KB (must be <= 30 KB)');
  }
  console.error('PERF-08: FAIL — ' + reasons.join('; '));
  process.exit(1);
}
