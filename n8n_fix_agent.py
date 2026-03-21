import subprocess, json, time

KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM3NzAzMC1jYTE5LTRjZDktYmVjNi1iYThlYzQ3MWE1MzciLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiZGViMzU5ZWItMTE1Ny00ZmY4LWFkNGMtY2U2N2U0N2JhMTQ5IiwiaWF0IjoxNzcyNDA0NTkwLCJleHAiOjE4MDM5NDA1ODk1MDZ9.SJgg4NSfeEXmv5laVgs8cyZvaIAdcYH_vwqs6NlqTeA'
WF_ID = '48lRw4rA1I2HA39g'

node_script = r"""
const http = require("http");
const KEY = process.argv[2];
const WF_ID = process.argv[3];

function req(method, path, body=null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : "";
    const opts = {
      hostname: "127.0.0.1", port: 5678,
      path, method,
      headers: {
        "X-N8N-API-KEY": KEY,
        "Content-Type": "application/json",
        ...(data ? {"Content-Length": Buffer.byteLength(data)} : {})
      }
    };
    const r = http.request(opts, res => {
      let d = ""; res.on("data", c=>d+=c);
      res.on("end", () => resolve({status: res.statusCode, body: d}));
    });
    r.on("error", reject);
    if (data) r.write(data);
    r.end();
  });
}

async function main() {
  // Check current state
  const s = await req("GET", `/api/v1/workflows/${WF_ID}`);
  console.log("GET status:", s.status);
  const wf = JSON.parse(s.body);
  console.log("Active:", wf.active);

  // Check webhook nodes
  for (const n of wf.nodes) {
    if (n.type === "n8n-nodes-base.webhook") {
      console.log("Webhook node:", n.name);
      console.log("  path:", n.parameters.path);
      console.log("  httpMethod:", n.parameters.httpMethod);
      console.log("  auth:", n.parameters.authentication);
      console.log("  credentials:", JSON.stringify(n.credentials));
    }
  }

  // Deactivate
  console.log("\n--- Deactivating ---");
  const d = await req("POST", `/api/v1/workflows/${WF_ID}/deactivate`);
  console.log("Deactivate status:", d.status, d.body.slice(0,100));

  await new Promise(r => setTimeout(r, 3000));

  // Activate
  console.log("\n--- Activating ---");
  const a = await req("POST", `/api/v1/workflows/${WF_ID}/activate`);
  console.log("Activate status:", a.status);
  const aData = JSON.parse(a.body);
  console.log("Active:", aData.active);
  if (a.status !== 200) console.log("Error:", a.body.slice(0,300));

  await new Promise(r => setTimeout(r, 2000));

  // Test webhook
  console.log("\n--- Testing webhook ---");
  const t = await new Promise((resolve, reject) => {
    const data = JSON.stringify({message: "hello", sessionId: "test-diag"});
    const opts = {
      hostname: "127.0.0.1", port: 5678,
      path: "/webhook/admin/chat", method: "POST",
      headers: {"Content-Type": "application/json", "Content-Length": Buffer.byteLength(data)}
    };
    const r = http.request(opts, res => {
      let d = ""; res.on("data", c=>d+=c);
      res.on("end", () => resolve({status: res.statusCode, body: d}));
    });
    r.on("error", reject);
    r.write(data); r.end();
  });
  console.log("Webhook test status:", t.status);
  console.log("Body:", t.body.slice(0,400));
}

main().catch(e => { console.error("ERROR:", e.message); process.exit(1); });
"""

with open("/tmp/n8n_agent_fix.js", "w") as f:
    f.write(node_script)

subprocess.run(["docker", "cp", "/tmp/n8n_agent_fix.js", "current-n8n-main-1:/tmp/n8n_agent_fix.js"])
result = subprocess.run(
    ["docker", "exec", "current-n8n-main-1", "node", "/tmp/n8n_agent_fix.js", KEY, WF_ID],
    capture_output=True, text=True, timeout=60
)
print(result.stdout)
if result.returncode != 0:
    print("STDERR:", result.stderr[:500])
