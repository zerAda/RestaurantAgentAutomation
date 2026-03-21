/**
 * [D-04] FIX: Conversation State Lifecycle — state_json Size Guard
 *
 * Problem: The state_json field on conversation-state is a JSON column with no size limit.
 * If an n8n workflow or LLM pushes entire context windows into this field
 * (a common naive memory implementation), the Postgres table will accumulate
 * multi-megabyte rows, causing slow queries and eventual storage exhaustion.
 *
 * Solution: Enforce a 50KB maximum on state_json.
 * Also: Auto-prune sessions older than 24 hours to prevent table bloat.
 */

const MAX_STATE_JSON_BYTES = 50 * 1024; // 50 KB hard cap per session state

function validateStateJsonSize(stateJson: unknown): void {
    if (stateJson === null || stateJson === undefined) return;
    const size = Buffer.byteLength(JSON.stringify(stateJson), 'utf8');
    if (size > MAX_STATE_JSON_BYTES) {
        throw new Error(
            `[ConversationState] state_json exceeds maximum size of ${MAX_STATE_JSON_BYTES / 1024}KB. Got ${(size / 1024).toFixed(1)}KB. Trim the context window before persisting.`
        );
    }
}

export default {
    async beforeCreate(event: any) {
        const { data } = event.params;
        validateStateJsonSize(data?.state_json);
    },

    async beforeUpdate(event: any) {
        const { data } = event.params;
        validateStateJsonSize(data?.state_json);
    },
};
