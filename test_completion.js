import { createOpenRouter } from '@openrouter/ai-sdk-provider';
import { generateText } from 'ai';
import * as dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.join(process.cwd(), '.env') });

const key = process.env.OPENROUTER_API_KEY;
if (!key) {
  console.error("❌ OPENROUTER_API_KEY not found");
  process.exit(1);
}

const openrouter = createOpenRouter({
  apiKey: key,
});

console.log("🚀 Starting completion test with moonshotai/kimi-k2.5...");

try {
  const { text } = await generateText({
    model: openrouter('moonshotai/kimi-k2.5'),
    prompt: 'Hello, are you operational? Answer with one word.',
    maxTokens: 10,
  });

  console.log(`✅ Success! Response: "${text}"`);
} catch (e) {
  console.error("❌ Completion Error:");
  if (e.response) {
      console.error(`Status: ${e.response.status}`);
      console.error(await e.response.text());
  } else {
      console.error(e);
  }
  process.exit(1);
}
