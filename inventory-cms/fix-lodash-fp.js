'use strict';
// Creates lodash/fp.mjs with explicit named ESM exports, and patches
// lodash/package.json with an exports map, for ALL nested lodash installs.
//
// Problem: @strapi/* packages each have their own nested node_modules/lodash.
// The ESM resolver uses the closest ancestor node_modules/lodash for each
// .mjs file, so we must patch EVERY lodash installation.
//
// Fixes:
//   import { get } from 'lodash/fp'      → ERR_UNSUPPORTED_DIR_IMPORT
//   import { get } from 'lodash/fp.js'   → named import from CJS fails
// Both resolved by exports map pointing ./fp → fp.mjs (ESM with named exports).
var fs = require('fs');
var path = require('path');

function findLodashDirs(searchRoot) {
  var results = [];
  function scan(dir, depth) {
    if (depth > 5) return;
    var entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (e) { return; }
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      if (!e.isDirectory()) continue;
      var full = path.join(dir, e.name);
      if (e.name === 'lodash') {
        // Only patch real lodash installs that have fp.js
        if (fs.existsSync(path.join(full, 'fp.js'))) results.push(full);
      } else if (e.name === 'node_modules' || e.name.charAt(0) === '@') {
        scan(full, depth + 1);
      }
    }
  }
  scan(searchRoot, 0);
  return results;
}

function patchLodash(dir) {
  var fp = require(dir + '/fp.js');
  var keys = Object.keys(fp);

  // Build the ESM wrapper with explicit named exports
  var lines = [
    "import _fp from './fp.js';",
    "export default _fp;"
  ];
  keys.forEach(function (k) {
    if (/^[a-zA-Z_$][a-zA-Z0-9_$]*$/.test(k)) {
      lines.push('export const ' + k + ' = _fp.' + k + ';');
    }
  });
  fs.writeFileSync(path.join(dir, 'fp.mjs'), lines.join('\n') + '\n');

  // Patch package.json exports map:
  //   "./fp"    — ESM import { x } from 'lodash/fp'  → fp.mjs (named exports)
  //   "./fp.js" — ESM import { x } from 'lodash/fp.js' → fp.mjs (named exports)
  //   "./*.js"  — explicit .js: require('lodash/get.js') → ./get.js (pass-through)
  //   "./*"     — bare import: require('lodash/get') → ./get.js (adds extension)
  var pkgPath = path.join(dir, 'package.json');
  var pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  pkg.exports = {
    '.': './lodash.js',
    './fp': { 'import': './fp.mjs', 'require': './fp.js' },
    './fp.js': { 'import': './fp.mjs', 'require': './fp.js' },
    './*.js': './*.js',
    './*': './*.js'
  };
  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
  console.log('Patched: ' + dir + ' (' + keys.length + ' exports)');
}

var dirs = findLodashDirs('/app/node_modules');
dirs.forEach(patchLodash);
console.log('Total lodash installs patched: ' + dirs.length);
