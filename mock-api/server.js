const http = require('http');

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', chunk => data += chunk);
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')); } catch { resolve({ raw: data }); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = req.url || '/';
  const body = await readBody(req);

  if (url.startsWith('/send/')) {
    const channel = url.split('/').pop();
    console.log(`[MOCK SEND] channel=${channel}`, body);
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ ok:true, channel, echo: body }));
  }

  if (url === '/alert') {
    console.log('[MOCK ALERT]', body);
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ ok:true }));
  }

  // Simple STT mock: returns text from "fakeTranscript" if provided
  if (url === '/asr') {
    const t = (body.fakeTranscript || '').toString().trim();
    res.writeHead(200, {'Content-Type':'application/json'});
    return res.end(JSON.stringify({ text: t || 'bonjour je veux une pizza', confidence: t ? 0.95 : 0.6, provider: 'mock' }));
  }

  res.writeHead(404, {'Content-Type':'application/json'});
  res.end(JSON.stringify({ ok:false, error:'not_found' }));
});

server.listen(8080, () => console.log('mock-api listening on :8080'));