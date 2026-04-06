import { createOpenRouter } from '@openrouter/ai-sdk-provider';
import { streamText } from 'ai';
import * as dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.join(process.cwd(), '.env') });

const key = process.env.OPENROUTER_API_KEY;
const openrouter = createOpenRouter({ apiKey: key });

console.log("🌊 Starting streaming test...");

try {
  const { textStream } = await streamText({
    model: openrouter('moonshotai/kimi-k2.5'),
    prompt: 'Tell me a short 3-sentence story.',
  });

  for await (const textPart of textStream) {
    process.stdout.write(textPart);
  }
  console.log("\n✅ Streaming complete!");
} catch (e) {
  console.error("\n❌ Streaming Error:");
  console.error(e);
  process.exit(1);
}
