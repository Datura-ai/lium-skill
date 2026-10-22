// Run: node --test chrome-extension/prices.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePrices, withUtm } from './prices.js';

const feed = {
  models: [
    { name: 'B200', url: 'https://lium.io/gpu/b200', min_price_usd_per_gpu_hour: 5.8, available_gpus: 16, vram_gb: 180 },
    { name: 'H100', url: 'https://lium.io/gpu/h100', min_price_usd_per_gpu_hour: 1.9, available_gpus: 40, vram_gb: 80 },
    { name: 'GB300', url: 'https://lium.io/gpu/gb300', min_price_usd_per_gpu_hour: 8, available_gpus: 0 },
    { name: 'A100', url: 'https://lium.io/gpu/a100', reference_price_usd_per_gpu_hour: 1.1, available_gpus: 2 },
    { name: 'Evil', url: 'https://evil.example/x', min_price_usd_per_gpu_hour: 0.5, available_gpus: 1 },
    { name: 'Bad', url: 'https://lium.io/gpu/bad', min_price_usd_per_gpu_hour: null, available_gpus: 3 },
  ],
};

test('available models only, cheapest first, reference price as fallback', () => {
  assert.deepEqual(parsePrices(feed).map((r) => [r.name, r.price]), [['Evil', 0.5], ['A100', 1.1], ['H100', 1.9], ['B200', 5.8]]);
});

test('links stay on lium.io and carry the UTM tag', () => {
  const rows = parsePrices(feed);
  assert.equal(rows.find((r) => r.name === 'Evil').url, 'https://lium.io/?utm_source=chrome-extension&utm_medium=extension&utm_campaign=gpu-prices');
  assert.equal(rows.find((r) => r.name === 'H100').url, 'https://lium.io/gpu/h100?utm_source=chrome-extension&utm_medium=extension&utm_campaign=gpu-prices');
  assert.equal(withUtm('https://lium.io/?gpu=H100'), 'https://lium.io/?gpu=H100&utm_source=chrome-extension&utm_medium=extension&utm_campaign=gpu-prices');
});

test('malformed feed gives no rows', () => {
  assert.deepEqual(parsePrices(null), []);
  assert.deepEqual(parsePrices({ models: 'x' }), []);
});
