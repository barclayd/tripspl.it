import { readFile, writeFile } from 'node:fs/promises';
import { URL } from 'node:url';
import { createOpenAPIContract, serializeOpenAPIContract } from '../src/contracts/openapi';
import { verifyContract } from './verify-contract';

const target = new URL('../contracts/openapi.json', import.meta.url);
const expected = serializeOpenAPIContract();
verifyContract(createOpenAPIContract());
const args = process.argv.slice(2);
if (args.some(argument => argument !== '--check')) throw new Error('Use --check to verify the committed contract, or no arguments to regenerate it.');

if (args.includes('--check')) {
  const existing = await readFile(target, 'utf8').catch(error => {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
    throw error;
  });
  if (existing !== expected) {
    console.error('The generated API contract is missing or stale. Run bun run contracts:generate and commit api/contracts/openapi.json.');
    process.exitCode = 1;
  } else {
    console.log('The generated API contract is current.');
  }
} else {
  await writeFile(target, expected);
  console.log('Generated contracts/openapi.json from the Hono route registry and Zod schemas.');
}
