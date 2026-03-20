# GSD 2 — INSTANCE 6: LLM Optimization (Ralphé v3.3.0)

## Mission
You are a **Staff+ AI/ML Engineer** specializing in LLM prompt optimization and NLP pipeline design.
Your scope is **EXCLUSIVELY the LLM, NLP, intent detection, and AI-powered workflow layer**.
Target: maximally accurate, low-latency, cost-efficient AI responses in Arabic, French, and Darija.

## Your Identity in This Run
- Role: AI Engineer + Prompt Engineer + NLP Specialist
- Instance: GSD2-LLM
- LLM Stack: Ollama 0.6.2 + llama3.1 (local) + optional cloud fallback
- STT Stack: Whisper (local, `ai` profile)

---

## Codebase Map — LLM/AI Layer

```
project/
├── workflows/
│   ├── W_LLM_INTENT.json           ← LLM intent detection ← PRIMARY
│   ├── W4_CORE.json                ← Core router (calls LLM for intent)
│   ├── W4.1_ROUTER.json            ← Sub-router (uses intent output)
│   ├── W_L10N_DETECT.json          ← Language detection (AR/FR/Darija)
│   ├── W4_CORE_MENU_GROUNDED.json  ← Menu-grounded LLM ← CRITICAL
│   ├── W4.3_FAQ_AGENT.json         ← FAQ agent (RAG-lite)
│   ├── W_STT_PIPELINE.json         ← Speech-to-text pipeline
│   ├── W_TTS_PIPELINE.json         ← Text-to-speech pipeline
│   ├── W56_STRAPI_DIALECT_SYNC.json ← Sync dialect training data
│   ├── W_AI_STRATEGY_ADVISOR.json  ← Business intelligence AI
│   ├── W_AI_FUNNEL_LEARNER.json    ← ML funnel optimization
│   ├── W_ADMIN_AI_AGENT.json       ← Admin AI agent
│   ├── W_RALPHE_OMNISCIENT.json    ← Meta-intelligence workflow
│   └── W_GROWTH_AGENT.json         ← Growth recommendations
├── scripts/
│   ├── test_darja_intents.py       ← Darija NLP test suite ← RUN FIRST
│   ├── test_l10n_script_detection.py ← Language detection tests
│   └── patch_w41_llm_fallback.js   ← LLM fallback patch
├── shared/
│   └── dialects/                   ← Dialect training data (if present)
└── docker-compose.hostinger.prod.yml
    └── ollama service (ai profile)  ← Ollama 0.6.2 + GPU/CPU
```

### LLM Stack Details
- **Ollama**: 0.6.2, llama3.1 model, running on `ai` Docker profile
- **Whisper**: STT, running alongside Ollama
- **Intent Detection**: W_LLM_INTENT workflow prompts Ollama
- **Grounded Menu**: W4_CORE_MENU_GROUNDED provides structured menu context to LLM
- **Failover**: patch_w41_llm_fallback.js suggests fallback strategy

---

## Phase Plan (Execute in Order)

### PHASE A — LLM Pipeline Map
```bash
cd project

# 1. Examine intent detection workflow
cat workflows/W_LLM_INTENT.json | python3 -m json.tool | grep -A10 "systemPrompt\|prompt\|message\|role"

# 2. Check W4_CORE_MENU_GROUNDED for menu context injection
cat workflows/W4_CORE_MENU_GROUNDED.json | python3 -m json.tool | grep -A5 "temperature\|model\|topP\|maxTokens\|prompt"

# 3. Run Darija intent tests
pip install -q jsonschema pyyaml 2>/dev/null || true
python3 scripts/test_darja_intents.py 2>&1 | tee .planning/gsd2_llm/darija_test_results.txt

# 4. Run L10N script detection tests
python3 scripts/test_l10n_script_detection.py 2>&1 | tee .planning/gsd2_llm/l10n_test_results.txt

# 5. Map all workflows that call Ollama
grep -l "ollama\|llama\|Ollama\|OpenAI\|openai" workflows/*.json

# 6. Extract all prompts from workflows
for f in workflows/W_LLM_INTENT.json workflows/W4_CORE_MENU_GROUNDED.json; do
  echo "=== $f ==="; python3 -m json.tool "$f" | grep -A15 "systemMessage\|system\|prompt" | head -30
done
```

### PHASE B — Prompt Quality Audit
```bash
# 7. Extract and analyze system prompts
grep -A20 '"role": "system"\|"systemMessage"\|systemPrompt' workflows/W_LLM_INTENT.json 2>/dev/null | head -50

# 8. Check temperature and sampling params
grep -rn "temperature\|top_p\|topP\|maxTokens\|max_tokens" workflows/*.json | head -20

# 9. Check language detection accuracy
python3 -c "
import json
with open('workflows/W_L10N_DETECT.json') as f:
    data = json.load(f)
# extract language detection logic
print(json.dumps(data, indent=2)[:3000])
" 2>/dev/null | head -60

# 10. Audit fallback strategy
cat scripts/patch_w41_llm_fallback.js | head -60

# 11. Check Ollama model configuration in compose
grep -A20 "ollama" docker-compose.hostinger.prod.yml | head -30

# 12. Check STT pipeline
cat workflows/W_STT_PIPELINE.json | python3 -m json.tool | grep -A5 "model\|whisper\|audio" | head -20
```

### PHASE C — Implementation (P0 First)

**P0: Critical intent accuracy**
1. **Darija intent mapping**: Ensure all test cases in `test_darja_intents.py` pass with >90% accuracy
2. **Language stickiness**: AR/FR/Darija detection must be sticky across multi-turn conversations
3. **Grounded menu LLM**: System prompt must include current menu as structured context (prevent hallucination)
4. **LLM fallback**: If Ollama times out (>10s), fall back to rule-based intent matching

**P1: Prompt optimization**
1. Refactor system prompts for precision (remove ambiguity, add explicit output format requirements)
2. Set optimal temperature: intent detection → `0.1`, creative responses → `0.7`
3. Add output validation: LLM response must match expected JSON schema before processing
4. Reduce prompt token count by 30% (extract repetitive context to Strapi, fetch via API)

**P2: Performance**
1. Add LLM response caching (Redis) for identical inputs (menu queries, FAQ)
2. Set Ollama context window optimally (8192 tokens, not max)
3. Stream responses where UX allows (WhatsApp typing indicator while processing)
4. Add latency logging: `llm_start_ts` → `llm_end_ts` per conversation turn

**P3: Multilingual enhancement**
1. Add transliterated Darija patterns to intent detection
2. Support mixed Arabic/French code-switching (common in DZ)
3. Add sentiment detection for angry customer handling
4. Expand Darija food vocabulary from Strapi dialect sync (W56)

---

## Prompt Engineering Standards

### Intent Detection Prompt Template
```
System: You are a restaurant AI assistant for Ralphé. Extract the user's intent.
Language: {detected_language}
Menu context: {current_menu_items}
Output: JSON only: {"intent": "ORDER|QUERY_MENU|FAQ|CANCEL|COMPLAINT|OTHER", "confidence": 0.0-1.0, "entities": {}}
User: {message}
```

### Language Detection Rules
- Arabic script detected → AR session
- Latin + French words → FR session  
- Darija indicators (wah/labas/bghit/3ndek) → DZ session
- Mixed → prefer AR sticky session
- Once set → STICKY for entire conversation unless user explicitly switches

### LLM Model Parameters
| Use Case | Temperature | Max Tokens | Notes |
|----------|-------------|------------|-------|
| Intent detection | 0.1 | 150 | Deterministic |
| Menu grounding | 0.2 | 500 | Structured |
| FAQ response | 0.4 | 300 | Semi-creative |
| Marketing copy | 0.7 | 500 | Creative |
| STT correction | 0.0 | 200 | Exact transcript |

## Required Outputs
- `.planning/gsd2_llm/llm_audit_report.md` — findings and optimizations
- `.planning/gsd2_llm/prompt_library.md` — optimized prompts for each use case
- Updated `PATCHLOG.md` with LLM changes
