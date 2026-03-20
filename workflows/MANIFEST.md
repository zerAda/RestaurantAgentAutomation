# Ralphé n8n Ecosystem Manifest

Total Workflows: 92


## 🏗️ Layer 0: Infrastructure & Core Utilities

- [W0_CONFIG_READER.json](file:///project/workflows/W0_CONFIG_READER.json): Central Hub for environment & tenant config.
- [W0_REDIS_HELPER.json](file:///project/workflows/W0_REDIS_HELPER.json): Abstracted Redis operations (Dedupe, State).
- [W8_OPS.json](file:///project/workflows/W8_OPS.json): Global Error Handling & Monitoring.
- [W15_OUTBOX_WORKER.json](file:///project/workflows/W15_OUTBOX_WORKER.json): Reliable outbound message delivery with Retry/DLQ.



## 🧠 Layer 1: AI Brains & Specialist Agents

- [W_RALPHE_OMNISCIENT.json](file:///project/workflows/W_RALPHE_OMNISCIENT.json): The Master Orchestrator.
- [W4_CORE.json](file:///project/workflows/W4_CORE.json): Real-time Conversation & Intent Processing.
- [W_AI_FUNNEL_LEARNER.json](file:///project/workflows/W_AI_FUNNEL_LEARNER.json): Conversion Intelligence (Marketing Loop Intake).
- [W_GROWTH_AGENT.json](file:///project/workflows/W_GROWTH_AGENT.json): Promo & Campaign generator.



## 🛒 Layer 2: Commerce & Financial Loops

- [W_PAYMENT_CALLBACK.json](file:///project/workflows/W_PAYMENT_CALLBACK.json): Secure payment verification (Chargily).
- [W4.2_CART_MANAGER.json](file:///project/workflows/W4.2_CART_MANAGER.json): State-safe cart operations.
- [W12_ADMIN_ORDERS.json](file:///project/workflows/W12_ADMIN_ORDERS.json): Order fulfillment & Admin views.



## 📡 Layer 3: Omnichannel Adapters

- W1_IN_WA, W2_IN_IG, W3_IN_MSG: Inbound normalization.
- W5_OUT_WA, W6_OUT_IG, W7_OUT_MSG: Outbound delivery.



## 🧪 Experimental / Stale (To Be Deprecated)

- W4_CORE_ALGERIAN_STUB.json: Redundant logic replaced by W4_CORE (Moved to DEPRECATED).
- W_INCEPTION_PROTOCOL.json: Specialized creative script gen (needs relocation).



## 📊 Business ROI Connection

- Tracking Funnel -> Funnel Learner -> Omniscient Brain -> Specialist Agents -> Outbound (WhatsApp).
