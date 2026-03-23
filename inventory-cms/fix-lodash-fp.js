'use strict';
// Creates lodash/fp.mjs with explicit named ESM exports and patches
// lodash/package.json with an exports map, for ALL nested lodash installs.
//
// Problem: every @strapi/* package bundles its own node_modules/lodash.
// ESM resolver uses nearest ancestor, so we must patch each one.
//
// Traversal: scan node_modules recursively (packages → their node_modules → ...)
var fs = require('fs');
var path = require('path');

function findLodashDirs(startNodeModules) {
  var results = [];

  function scanNodeModules(nmDir, depth) {
    if (depth > 5) return;
    var entries;
    try { entries = fs.readdirSync(nmDir, { withFileTypes: true }); }
    catch (e) { return; }

    entries.forEach(function (e) {
      if (!e.isDirectory()) return;
      var pkgDir = path.join(nmDir, e.name);

      if (e.name === 'lodash') {
        // Found a lodash install — check it has fp.js
        if (fs.existsSync(path.join(pkgDir, 'fp.js'))) {
          results.push(pkgDir);
        }
      } else if (e.name.charAt(0) === '@') {
        // Scoped namespace: look one level deeper for actual packages
        var scopedEntries;
        try { scopedEntries = fs.readdirSync(pkgDir, { withFileTypes: true }); }
        catch (err) { return; }
        scopedEntries.forEach(function (se) {
          if (!se.isDirectory()) return;
          var scopedPkg = path.join(pkgDir, se.name);
          var nested = path.join(scopedPkg, 'node_modules');
          if (fs.existsSync(nested)) scanNodeModules(nested, depth + 1);
        });
      } else {
        // Regular package: check for its own node_modules
        var nested = path.join(pkgDir, 'node_modules');
        if (fs.existsSync(nested)) scanNodeModules(nested, depth + 1);
      }
    });
  }

  scanNodeModules(startNodeModules, 0);
  return results;
}

function patchLodash(dir) {
  var fp = require(dir + '/fp.js');
  var keys = Object.keys(fp);

  // ESM wrapper with all named exports
  var lines = ["import _fp from './fp.js';", "export default _fp;"];
  keys.forEach(function (k) {
    if (/^[a-zA-Z_$][a-zA-Z0-9_$]*$/.test(k)) {
      lines.push('export const ' + k + ' = _fp.' + k + ';');
    }
  });
  fs.writeFileSync(path.join(dir, 'fp.mjs'), lines.join('\n') + '\n');

  // Exports map:
  //   "./fp"    → fp.mjs  (fixes ERR_UNSUPPORTED_DIR_IMPORT + named import)
  //   "./fp.js" → fp.mjs  (handles previously-patched direct .js imports)
  //   "./*.js"  → ./*.js  (explicit .js: require('lodash/get.js') → ./get.js)
  //   "./*"     → ./*.js  (bare: require('lodash/get') → ./get.js)
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
  console.log('Patched: ' + dir.replace('/app/node_modules/', '') + ' (' + keys.length + ' exports)');
}

var dirs = findLodashDirs('/app/node_modules');
dirs.forEach(patchLodash);
console.log('Total lodash installs patched: ' + dirs.length);
