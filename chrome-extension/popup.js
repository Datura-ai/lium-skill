import { parsePrices } from './prices.js';

const status = document.getElementById('status');

function cell(text, cls) {
  const td = document.createElement('td');
  if (cls) td.className = cls;
  td.append(text);
  return td;
}

try {
  const res = await fetch('https://lium.io/pricing.json', { cache: 'no-store' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const rows = parsePrices(await res.json());
  const tbody = document.getElementById('rows');
  for (const r of rows) {
    const a = document.createElement('a');
    a.href = r.url;
    a.target = '_blank';
    a.rel = 'noopener';
    a.textContent = r.name;
    const tr = document.createElement('tr');
    tr.append(cell(a), cell(r.vram ? `${r.vram} GB` : '–', 'num'), cell(String(r.available), 'num'), cell(`$${r.price.toFixed(2)}`, 'num'));
    tbody.append(tr);
  }
  document.querySelector('table').hidden = rows.length === 0;
  status.textContent = rows.length ? `${rows.length} GPU models available now, cheapest first.` : 'No GPUs available right now.';
} catch (e) {
  status.textContent = `Could not load prices (${e.message}). Open lium.io for current prices.`;
}
