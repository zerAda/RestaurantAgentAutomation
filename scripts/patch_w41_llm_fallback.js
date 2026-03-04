const fs = require('fs');
const targetFile = 'c:/Users/mon pc/Desktop/ralphé_final_patch/project/workflows/W4.1_ROUTER.json';
let w = JSON.parse(fs.readFileSync(targetFile, 'utf8'));

let c6 = w.nodes.find(n => n.name === 'C6 - Router (safe, LLM optional)');
if (c6) {
    let js = c6.parameters.jsCode;
    const catchRegex = /\\} catch \\(err\\) \\{[\\s\\S]*?\\}/;

    const fallbackLogic = `} catch (err) {
    // SELF-HEALING LLM FALLBACK //
    try {
      e.debug.llm_primary_failed = true;
      const fallbackUrl = (cfg.llm_fallback_url || $env.LLM_FALLBACK_URL || 'https://api.groq.com/openai/v1/chat/completions').toString();
      const fallbackKey = (cfg.llm_fallback_key || $env.LLM_FALLBACK_KEY || '').toString();
      
      if (fallbackUrl && fallbackKey) {
        const fallbackRes = await $httpRequest({
          method:'POST',
          url: fallbackUrl,
          headerParameters: { Authorization: \`Bearer \${fallbackKey}\` },
          body: { 
            model: cfg.llm_fallback_model || $env.LLM_FALLBACK_MODEL || 'llama3-70b-8192',
            messages: [{ role: 'system', content: prompt }],
            response_format: { type: 'json_object' }
          },
          json: true,
          timeout: 10000
        });
        
        const rawFallback = fallbackRes.choices?.[0]?.message?.content || '{}';
        const parsed = JSON.parse(rawFallback);
        // ... (Map fallback response just like primary)
        if (parsed.action === 'menu') {
          return [{json:{...e, intent:'SHOW_MENU', response:{replyText:'Tape MENU pour afficher le menu.', buttons:[{id:'HELP_MENU',title:'📋 Menu'}]}, debug:{riskFlags, llm:true, fallback_used:true}}}];
        }
        if (parsed.action === 'checkout') {
          return [{json:{...e, intent:'CONFIRM', response:{replyText:'Clique ✅ Valider pour confirmer.', buttons:[{id:'CHECKOUT',title:'✅ Valider'}]}, debug:{riskFlags, llm:true, fallback_used:true}}}];
        }
        if (parsed.action === 'add' && Array.isArray(parsed.lines) && parsed.lines.length) {
          const codes = parsed.lines.map(l => l.item).filter(Boolean);
          if (!codes.length) throw new Error('Fallback LLM lines missing item');
          return [{json:{...e, intent:'CLARIFY', response:{replyText:'Pour être sûr, peux-tu renvoyer les IDs comme ceci : ' + codes.join(' ') + ' (ex: P01 x2) ?', buttons:[{id:'HELP_MENU',title:'📋 Menu'}]}, debug:{riskFlags, llm:true, fallback_used:true}}}];
        }
      }
    } catch (fallbackErr) {
      // both failed, proceed to default clarify
    }
  }`;

    c6.parameters.jsCode = js.replace(catchRegex, fallbackLogic);
    fs.writeFileSync(targetFile, JSON.stringify(w, null, 2));
    console.log('Successfully patched W4.1 for Self-Healing LLM!');
} else {
    console.log('C6 Node not found in W4.1');
}
