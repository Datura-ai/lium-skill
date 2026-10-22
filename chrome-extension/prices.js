// Turns https://lium.io/pricing.json into popup rows. Pure, so it is testable in node (prices.test.mjs).
const UTM = 'utm_source=chrome-extension&utm_medium=extension&utm_campaign=gpu-prices';

export function withUtm(url) {
  const u = new URL(url);
  // the feed is remote data: only ever link to lium.io
  if (u.protocol !== 'https:' || u.hostname !== 'lium.io') return `https://lium.io/?${UTM}`;
  u.search = u.search ? `${u.search.slice(1)}&${UTM}` : UTM;
  return u.toString();
}

export function parsePrices(feed) {
  const models = Array.isArray(feed?.models) ? feed.models : [];
  return models
    .map((m) => ({
      name: String(m.name || m.gpu_model || m.model || ''),
      price: Number(m.min_price_usd_per_gpu_hour ?? m.reference_price_usd_per_gpu_hour),
      available: Number(m.available_gpus) || 0,
      vram: Number(m.vram_gb) || null,
      url: withUtm(m.url || 'https://lium.io/'),
    }))
    .filter((r) => r.name && r.available > 0 && Number.isFinite(r.price) && r.price > 0)
    .sort((a, b) => a.price - b.price || a.name.localeCompare(b.name));
}
