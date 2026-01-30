#!/usr/bin/env node
/**
 * P1-06: Patch workflows for structured logging + correlation propagation
 *
 * This script modifies W1/W2/W3 (inbound), W4 (core), and W5/W6/W7 (outbound)
 * to add structured logging with correlation_id propagation and secret masking.
 */

const fs = require('fs');
const path = require('path');

const WORKFLOWS_DIR = path.join(__dirname, '..', 'workflows');

// Structured logging helper code to inject at the beginning of parse nodes
const LOGGING_HELPER = `
// =============================================================================
// P1-06: Structured Logging Helper with Secret Masking
// =============================================================================
const _logLevel = ($env.LOG_LEVEL || 'INFO').toString().toUpperCase();
const _logStructured = (($env.LOG_STRUCTURED || 'true').toString().toLowerCase() === 'true');
const _logMaskPatterns = ($env.LOG_MASK_PATTERNS || 'token,password,secret,api_key,authorization,bearer').toString()
  .split(',').map(p => p.trim().toLowerCase()).filter(Boolean);

function _maskSecrets(obj, depth = 0) {
  if (depth > 10) return '[MAX_DEPTH]';
  if (obj === null || obj === undefined) return obj;
  if (typeof obj === 'string') {
    if (obj.length > 20 && /^[A-Za-z0-9_\\-\\.]+$/.test(obj)) return '[REDACTED]';
    return obj;
  }
  if (typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(v => _maskSecrets(v, depth + 1));
  const masked = {};
  for (const [k, v] of Object.entries(obj)) {
    const kLower = k.toLowerCase();
    if (_logMaskPatterns.some(p => kLower.includes(p))) {
      masked[k] = '[REDACTED]';
    } else if (typeof v === 'object' && v !== null) {
      masked[k] = _maskSecrets(v, depth + 1);
    } else if (typeof v === 'string' && v.length > 20 && /^[A-Za-z0-9_\\-\\.]+$/.test(v)) {
      masked[k] = '[REDACTED]';
    } else {
      masked[k] = v;
    }
  }
  return masked;
}

const _levelMap = { DEBUG: 0, INFO: 1, WARN: 2, ERROR: 3 };
const _currentLevel = _levelMap[_logLevel] || 1;
const _logEntries = [];

function _slog(level, eventType, message, context = {}) {
  const lvl = _levelMap[level] || 1;
  if (lvl < _currentLevel) return;
  _logEntries.push({
    timestamp: new Date().toISOString(),
    level,
    event_type: eventType,
    message,
    context: _maskSecrets(context)
  });
}
// End P1-06 Logging Helper
`;

// Update W1/W2/W3 inbound workflows to propagate correlation_id in _log field
function patchInboundWorkflow(wfPath, channel) {
  console.log(`Patching ${path.basename(wfPath)}...`);
  const wf = JSON.parse(fs.readFileSync(wfPath, 'utf8'));
  let modified = false;

  // Find the B0 - Parse & Canonicalize node
  for (const node of wf.nodes) {
    if (node.name === 'B0 - Parse & Canonicalize') {
      let code = node.parameters.jsCode || '';

      // Check if already patched
      if (code.includes('P1-06')) {
        console.log('  Already patched, skipping...');
        return false;
      }

      // Add logging helper after the initial requires
      const requiresEnd = code.indexOf("const rawBodyInput");
      if (requiresEnd === -1) {
        console.log('  Could not find injection point, skipping...');
        return false;
      }

      // Insert logging helper
      code = code.slice(0, requiresEnd) + LOGGING_HELPER + '\n' + code.slice(requiresEnd);

      // Add log entry for inbound received
      const returnIndex = code.lastIndexOf('return [{');
      if (returnIndex !== -1) {
        const logCall = `
// P1-06: Log inbound receipt
_slog('INFO', 'INBOUND_RECEIVED', '${channel} message received', {
  msgId: msgId || 'unknown',
  userId: userId || 'unknown',
  msgType: type,
  isMetaNative,
  isStatusUpdate,
  ip: ip || 'unknown'
});

`;
        code = code.slice(0, returnIndex) + logCall + code.slice(returnIndex);
      }

      // Add _log entries to the output
      code = code.replace(
        '_sec: {\\n      textHash\\n    },',
        '_sec: {\\n      textHash\\n    },\\n    _log: {\\n      entries: _logEntries,\\n      workflow: \\'W' + channel.charAt(0).toUpperCase() + '_IN_' + channel.toUpperCase().slice(0, 2) + '\\'\\n    },'
      );

      // Fallback: add _log after _sec if pattern not found
      if (!code.includes('_log: {')) {
        code = code.replace(
          '"_sec": {',
          '"_log": { "entries": _logEntries, "workflow": "' + 'W_IN_' + channel.toUpperCase().slice(0, 2) + '" },\\n    "_sec": {'
        );
      }

      node.parameters.jsCode = code;
      modified = true;
      break;
    }
  }

  if (modified) {
    fs.writeFileSync(wfPath, JSON.stringify(wf, null, 2));
    console.log('  Patched successfully');
    return true;
  }
  return false;
}

// Update W4 CORE to propagate correlation_id
function patchCoreWorkflow(wfPath) {
  console.log('Patching W4_CORE.json...');
  const wf = JSON.parse(fs.readFileSync(wfPath, 'utf8'));
  let modified = false;

  // Find the C0 - Validate Event node
  for (const node of wf.nodes) {
    if (node.name === 'C0 - Validate Event') {
      let code = node.parameters.jsCode || '';

      if (code.includes('P1-06')) {
        console.log('  Already patched, skipping...');
        return false;
      }

      // Add correlation_id propagation
      const newCode = `// P1-06: Preserve correlation_id from inbound
const _correlationId = $json._timing?.correlation_id || $json.correlation_id || '';
const _logEntries = $json._log?.entries || [];
` + code;

      // Ensure correlation_id is in output
      const returnMatch = code.match(/return \[\{json:\s*\{\s*\.\.\.\s*e/);
      if (returnMatch) {
        code = newCode.replace(
          'return [{json: { ...e',
          'return [{json: { ...e, _timing: { ...e._timing, correlation_id: _correlationId }, _log: { entries: _logEntries, workflow: "W4_CORE" }'
        );
      } else {
        code = newCode;
      }

      node.parameters.jsCode = code;
      modified = true;
      break;
    }
  }

  // Find C11 - Finalize Response node and ensure correlation_id is passed to outbound
  for (const node of wf.nodes) {
    if (node.name === 'C11 - Finalize Response (default)') {
      let code = node.parameters.jsCode || '';

      if (code.includes('correlation_id')) {
        continue;
      }

      // Add correlation_id to output
      code = code.replace(
        "const out = {",
        "const correlationId = e._timing?.correlation_id || '';\nconst out = {"
      );
      code = code.replace(
        "debug: {",
        "correlation_id: correlationId,\n  _timing: e._timing || {},\n  debug: {"
      );

      node.parameters.jsCode = code;
      modified = true;
    }
  }

  if (modified) {
    fs.writeFileSync(wfPath, JSON.stringify(wf, null, 2));
    console.log('  Patched successfully');
    return true;
  }
  return false;
}

// Update W5/W6/W7 outbound workflows to use correlation_id
function patchOutboundWorkflow(wfPath, channel) {
  console.log(`Patching ${path.basename(wfPath)}...`);
  const wf = JSON.parse(fs.readFileSync(wfPath, 'utf8'));
  let modified = false;

  // Find the B0 - Prepare Outbox node
  for (const node of wf.nodes) {
    if (node.name === 'B0 - Prepare Outbox') {
      let code = node.parameters.jsCode || '';

      if (code.includes('correlation_id') && code.includes('P1-06')) {
        console.log('  Already patched, skipping...');
        return false;
      }

      // Add correlation_id to outbox entry
      code = code.replace(
        "const payload = $json;",
        "const payload = $json;\n// P1-06: Get correlation_id from CORE\nconst correlationId = payload._timing?.correlation_id || payload.correlation_id || '';"
      );

      code = code.replace(
        "const outboxEntry = {",
        "const outboxEntry = {\n  correlation_id: correlationId,"
      );

      // Add to output _outbox object
      code = code.replace(
        "asyncEnabled",
        "asyncEnabled,\n      correlation_id: correlationId"
      );

      node.parameters.jsCode = code;
      modified = true;
      break;
    }
  }

  // Find END nodes and add correlation_id to final output
  for (const node of wf.nodes) {
    if (node.name && node.name.startsWith('END -')) {
      let code = node.parameters?.jsCode || '';

      if (!code || code.includes('correlation_id')) {
        continue;
      }

      // Add correlation_id to output
      code = code.replace(
        "const payload = $json;",
        "const payload = $json;\nconst correlationId = payload._outbox?.correlation_id || payload._timing?.correlation_id || '';"
      );

      code = code.replace(
        "return [{ json: {",
        "return [{ json: {\n  correlation_id: correlationId,"
      );

      if (node.parameters) {
        node.parameters.jsCode = code;
        modified = true;
      }
    }
  }

  if (modified) {
    fs.writeFileSync(wfPath, JSON.stringify(wf, null, 2));
    console.log('  Patched successfully');
    return true;
  }
  return false;
}

// Main execution
console.log('P1-06: Patching workflows for structured logging...\n');

let patchCount = 0;

// Patch inbound workflows
const inboundFiles = [
  { file: 'W1_IN_WA.json', channel: 'whatsapp' },
  { file: 'W2_IN_IG.json', channel: 'instagram' },
  { file: 'W3_IN_MSG.json', channel: 'messenger' }
];

for (const { file, channel } of inboundFiles) {
  const wfPath = path.join(WORKFLOWS_DIR, file);
  if (fs.existsSync(wfPath)) {
    if (patchInboundWorkflow(wfPath, channel)) patchCount++;
  } else {
    console.log(`  ${file} not found, skipping...`);
  }
}

// Patch CORE workflow
const corePath = path.join(WORKFLOWS_DIR, 'W4_CORE.json');
if (fs.existsSync(corePath)) {
  if (patchCoreWorkflow(corePath)) patchCount++;
} else {
  console.log('  W4_CORE.json not found, skipping...');
}

// Patch outbound workflows
const outboundFiles = [
  { file: 'W5_OUT_WA.json', channel: 'whatsapp' },
  { file: 'W6_OUT_IG.json', channel: 'instagram' },
  { file: 'W7_OUT_MSG.json', channel: 'messenger' }
];

for (const { file, channel } of outboundFiles) {
  const wfPath = path.join(WORKFLOWS_DIR, file);
  if (fs.existsSync(wfPath)) {
    if (patchOutboundWorkflow(wfPath, channel)) patchCount++;
  } else {
    console.log(`  ${file} not found, skipping...`);
  }
}

console.log(`\nDone! Patched ${patchCount} workflow(s).`);
