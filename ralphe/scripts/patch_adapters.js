const fs = require('fs');
const path = require('path');

const workflowsDir = path.join('c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows');

const patchJsCode = (originalJsCode, provider) => {
    const metaNativeParser = `
function extractAttachments(msg) {
  const attachments = [];
  if (msg?.attachments && Array.isArray(msg.attachments)) {
    for (const a of msg.attachments) {
      if (a.type === 'audio' && a.payload?.url) {
        attachments.push({ type: 'audio', url: a.payload.url, mime: 'audio/mp4' });
      } else if (a.type === 'image' && a.payload?.url) {
        attachments.push({ type: 'image', url: a.payload.url, mime: 'image/jpeg' });
      } else if (a.type === 'video' && a.payload?.url) {
        attachments.push({ type: 'video', url: a.payload.url, mime: 'video/mp4' });
      } else if (a.type === 'file' && a.payload?.url) {
        attachments.push({ type: 'document', url: a.payload.url, mime: 'application/octet-stream' });
      } else if (a.type === 'ig_voice' && a.payload?.url) {
        attachments.push({ type: 'audio', url: a.payload.url, mime: 'audio/mp4' });
      }
    }
  }
  return attachments;
}

function parseMetaNative(rawBody) {
  if (!rawBody || typeof rawBody !== 'object') return null;
  if (rawBody.object !== 'page' && rawBody.object !== 'instagram') return null;
  
  const entry = rawBody.entry?.[0];
  if (!entry) return null;
  
  const messaging = entry.messaging?.[0];
  if (!messaging) return null;
  
  if (messaging.delivery || messaging.read || messaging.optin) {
    return { _isStatusUpdate: true, _ignore: true };
  }
  
  const msg = messaging.message;
  if (!msg && !messaging.postback) return null;
  
  let text = msg?.text || messaging.postback?.payload || messaging.postback?.title || '';
  
  // Convert epoch timestamp to ISO 8601
  const epochTs = messaging.timestamp;
  let isoTimestamp;
  if (epochTs) {
    const epochNum = Number(epochTs);
    const msTs = epochNum > 9999999999 ? epochNum : epochNum * 1000;
    isoTimestamp = new Date(msTs).toISOString();
  } else {
    isoTimestamp = new Date().toISOString();
  }
  
  const provider = rawBody.object === 'instagram' ? 'ig' : 'msg';
  
  return {
    _isMetaNative: true,
    provider,
    msg_id: msg?.mid || messaging.postback?.mid || '',
    from: messaging.sender?.id || '',
    text: text,
    timestamp: isoTimestamp,
    attachments: extractAttachments(msg),
    meta: {
      recipient_id: messaging.recipient?.id || '',
    },
    raw_meta_message: msg || messaging.postback
  };
}

const rawBodyInput = $json.body ?? $json;
const metaNativeParsed = parseMetaNative(rawBodyInput);

let body;
let isMetaNative = false;
let isStatusUpdate = false;

if (metaNativeParsed && metaNativeParsed._isStatusUpdate) {
  isStatusUpdate = true;
  body = rawBodyInput;
} else if (metaNativeParsed && metaNativeParsed._isMetaNative) {
  isMetaNative = true;
  body = metaNativeParsed;
} else {
  body = rawBodyInput;
}
`;

    // We need to replace the start of the original JS code up to "const headers = ..."
    const headerStart = originalJsCode.indexOf('const headers =');
    if (headerStart === -1) {
        console.log('Could not find headers start in original JS code');
        return originalJsCode;
    }
    const latterPart = originalJsCode.substring(headerStart);

    // We also need to fix buildEnvelopeLegacy to use inboundReceivedAt
    // And fix the status update skip logic

    let updatedLatterPart = latterPart.replace(
        `let envelope;`,
        `let envelope;\n\nif (isStatusUpdate) {\n  normalizedVersion = 'v1';\n  envelope = {\n    contract_version: 'v1',\n    provider: '${provider}',\n    msg_id: 'status_update',\n    from: 'status_update',\n    text: '',\n    timestamp: inboundReceivedAt,\n    attachments: [],\n    meta: { status_update: true },\n    tenant_context: { source: 'status_update', hints: {} }\n  };\n}`
    );

    // Replace the block evaluating the generic envelope
    updatedLatterPart = updatedLatterPart.replace(
        /if \(normalizedVersion === 'unknown'\) \{[\s\S]*?\} else \{[\s\S]*?\n\}/,
        `else if (normalizedVersion === 'unknown') {
  envelope = null;
} else if (normalizedVersion === 'v2') {
  envelope = buildEnvelopeFromV2(body);
} else if (normalizedVersion === 'v1' && looksLikeV1 && !looksLikeV2) {
  envelope = buildEnvelopeFromV1(body);
} else {
  normalizedVersion = 'v1';
  envelope = buildEnvelopeLegacy();
}`
    );

    // Update validation logic to allow status updates
    updatedLatterPart = updatedLatterPart.replace(
        /let isValid = false;/,
        `let isValid = isStatusUpdate ? true : false;`
    );

    // Add _metaParsing mapping
    updatedLatterPart = updatedLatterPart.replace(
        `channel: ch,`,
        `channel: ch,\n    _metaParsing: {\n      isMetaNative,\n      isStatusUpdate,\n      rawBodyType: rawBodyInput?.object || 'legacy'\n    },`
    );

    return metaNativeParser + '\n' + updatedLatterPart;
};

const processWorkflow = (filename, provider) => {
    const filePath = path.join(workflowsDir, filename);
    if (!fs.existsSync(filePath)) {
        console.log(`Skipping \${filename} (not found)`);
        return;
    }
    const w = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const parseNode = w.nodes.find(n => n.name === 'B0 - Parse & Canonicalize');

    if (parseNode) {
        if (!parseNode.parameters.jsCode.includes('parseMetaNative')) {
            parseNode.parameters.jsCode = patchJsCode(parseNode.parameters.jsCode, provider);

            // Ensure B0 - Contract Valid? ignores status updates
            const validNode = w.nodes.find(n => n.name === 'B0 - Contract Valid?');
            if (validNode) {
                validNode.parameters.conditions.boolean[0].value1 = "={{$json._contract.isValid && !$json._metaParsing?.isStatusUpdate}}";
            }

            fs.writeFileSync(filePath, JSON.stringify(w, null, 2));
            console.log(`Successfully patched \${filename}`);
        } else {
            console.log(`\${filename} is already patched.`);
        }
    } else {
        console.log(`\${filename} has no 'B0 - Parse & Canonicalize' node.`);
    }
};

processWorkflow('W2_IN_IG.json', 'ig');
processWorkflow('W3_IN_MSG.json', 'msg');
