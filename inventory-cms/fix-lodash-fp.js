'use strict';
// Creates lodash/fp.mjs with explicit named ESM exports, and patches
// lodash/package.json with an exports map so that both:
//   import { get } from 'lodash/fp'      (directory import — ERR_UNSUPPORTED_DIR_IMPORT)
//   import { get } from 'lodash/fp.js'   (CJS without static named exports)
// resolve to lodash/fp.mjs which has proper named exports.
var fs = require('fs');
var dir = '/app/node_modules/lodash';

// Load fp via CJS require so we can enumerate all exported function names
var fp = require(dir + '/fp.js');
var keys = Object.keys(fp);

// Build the ESM wrapper
var lines = [
  "import _fp from './fp.js';",
  "export default _fp;"
];
keys.forEach(function(k) {
  // Only export valid JS identifiers (all lodash/fp exports are, but be safe)
  if (/^[a-zA-Z_$][a-zA-Z0-9_$]*$/.test(k)) {
    lines.push('export const ' + k + ' = _fp.' + k + ';');
  }
});
fs.writeFileSync(dir + '/fp.mjs', lines.join('\n') + '\n');
console.log('Created lodash/fp.mjs with ' + keys.length + ' named exports');

// Patch lodash package.json with an exports map
// "./fp"    — covers unpatched files: import { x } from 'lodash/fp'
// "./fp.js" — covers previously-patched files: import { x } from 'lodash/fp.js'
// "./*"     — wildcard preserves individual function imports like 'lodash/get'
var pkgPath = dir + '/package.json';
var pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.exports = {
  '.': './lodash.js',
  './fp': { 'import': './fp.mjs', 'require': './fp.js' },
  './fp.js': { 'import': './fp.mjs', 'require': './fp.js' },
  './*': './*'
};
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
console.log('Patched lodash/package.json with exports map');
