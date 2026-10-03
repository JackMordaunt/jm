// tokens.mjs writes tokens/primer.resolved.json from the pinned
// @primer/primitives docs in upstream/npm/primitives/dist/docs: every token
// keyed by its CSS custom property name (--fgColor-default), its value in
// the light theme, and its value in each other theme where it differs.
// Size tokens with a coarse-pointer twin carry it as the coarse mode.
//
//   node scripts/tokens.mjs    (from the kit root; just primer-kit-tokens)
import { readFileSync, writeFileSync, writeSync, readdirSync } from 'node:fs';

const docs = 'upstream/npm/primitives/dist/docs';
const commit = readFileSync('upstream/COMMIT', 'utf8').trim();
const version = JSON.parse(readFileSync('upstream/npm/primitives/package.json', 'utf8')).version;
const read = f => JSON.parse(readFileSync(`${docs}/${f}`, 'utf8'));

// The light theme is the value; every other theme is a mode key.
const THEMES = {
  light: 'value', dark: 'dark', 'dark-dimmed': 'darkDimmed',
  'light-high-contrast': 'lightHighContrast', 'dark-high-contrast': 'darkHighContrast',
  'dark-dimmed-high-contrast': 'darkDimmedHighContrast',
  'light-colorblind': 'lightColorblind', 'dark-colorblind': 'darkColorblind',
  'light-colorblind-high-contrast': 'lightColorblindHighContrast',
  'dark-colorblind-high-contrast': 'darkColorblindHighContrast',
  'light-tritanopia': 'lightTritanopia', 'dark-tritanopia': 'darkTritanopia',
  'light-tritanopia-high-contrast': 'lightTritanopiaHighContrast',
  'dark-tritanopia-high-contrast': 'darkTritanopiaHighContrast',
};
const files = readdirSync(`${docs}/functional/themes`).map(f => f.replace(/\.json$/, '')).sort();
if (JSON.stringify(files) !== JSON.stringify(Object.keys(THEMES).sort())) {
  throw new Error(`themes in the package (${files}) are not the kit's (${Object.keys(THEMES)})`);
}
// Theme-independent files; size-fine is the default density, size-coarse its twin.
const PLAIN = [
  'base/size/size.json', 'base/size/z-index.json', 'base/typography/typography.json', 'base/motion/motion.json',
  'functional/size/size.json', 'functional/size/size-fine.json', 'functional/size/border.json',
  'functional/size/radius.json', 'functional/size/breakpoints.json', 'functional/size/viewport.json',
  'functional/size/z-index.json', 'functional/spacing/space.json', 'functional/typography/typography.json',
  'functional/motion/motion.json',
];

function color(v) {
  if (/^#[0-9a-fA-F]{6}$/.test(v) || /^#[0-9a-fA-F]{8}$/.test(v)) return v.toLowerCase();
  if (v === 'transparent') return '#00000000';
  throw new Error(`colour ${v}`);
}
// px is a CSS length in px: rem and px convert, em stays relative.
function px(v) {
  const m = /^(-?[\d.]+)(rem|px)?$/.exec(v);
  if (!m) throw new Error(`length ${v}`);
  return m[2] === 'rem' ? Number(m[1]) * 16 : Number(m[1]);
}
function dimension(v) {
  const em = /^(-?[\d.]+)em$/.exec(v);
  return em ? { value: Number(em[1]), unit: 'em' } : px(v);
}
// A CSS box-shadow list: layers of {x, y, blur, spread, color, inset}.
function shadow(v) {
  return v.split(/,\s*(?=inset |-?[\d.]+(?:px|rem)? )/).map(layer => {
    const parts = layer.trim().split(/\s+/);
    const inset = parts[0] === 'inset';
    if (inset) parts.shift();
    const c = color(parts.pop());
    const n = parts.map(px);
    if (n.length < 2 || n.length > 4) throw new Error(`shadow layer ${layer}`);
    const [x, y, blur = 0, spread = 0] = n;
    return { x, y, blur, spread, color: c, inset };
  });
}
// A CSS font shorthand: weight size/line-height family, line height in px.
function typography(v) {
  const m = /^(\d+) ([\d.]+(?:rem|em))(?:\/([\d.]+))? (.+)$/.exec(v);
  if (!m) throw new Error(`typography ${v}`);
  const size = dimension(m[2]);
  const t = { fontWeight: Number(m[1]), fontSize: size, fontFamily: m[4] };
  if (m[3] !== undefined) t.lineHeight = typeof size === 'number' ? Number(m[3]) * size : Number(m[3]);
  return t;
}
function border(v) {
  const m = /^(\S+) (solid|dashed) (\S+)$/.exec(v);
  if (!m) throw new Error(`border ${v}`);
  return { width: px(m[1]), style: m[2], color: color(m[3]) };
}
function convert(type, v) {
  switch (type) {
    case 'color': return color(v);
    case 'dimension': return dimension(v);
    case 'number': case 'fontWeight': return Number(v);
    case 'duration': if (v.unit !== 'ms') throw new Error(`duration ${JSON.stringify(v)}`); return v.value;
    case 'cubicBezier': return v;
    case 'transition': return { duration: convert('duration', v.duration), timingFunction: v.timingFunction };
    case 'shadow': return shadow(v);
    case 'border': return border(v);
    case 'typography': return typography(v);
    case 'fontFamily': case 'custom-string': case 'custom-viewportRange': return v;
  }
  throw new Error(`unknown type ${type}`);
}
// "{fgColor.default}" is --fgColor-default; a base colour stays a base path.
function alias(a) {
  if (a === undefined) return undefined;
  const m = /^\{([^}]+)\}$/.exec(a);
  if (!m) return undefined;
  return m[1].startsWith('base.color.') ? m[1] : `--${m[1].replaceAll('.', '-')}`;
}

const tokens = {};
function put(name, entry, mode, file) {
  const key = `--${name}`;
  const v = convert(entry.type, entry.value);
  const t = tokens[key];
  if (mode === 'value') {
    if (t && JSON.stringify(t.value) !== JSON.stringify(v)) throw new Error(`${key} in ${file} disagrees with an earlier file`);
    tokens[key] = t ?? { type: entry.type, value: v, ...(alias(entry.alias) ? { alias: alias(entry.alias) } : {}) };
    return;
  }
  if (!t) throw new Error(`${key} is in ${file} but not the light theme`);
  if (JSON.stringify(t.value) !== JSON.stringify(v)) t[mode] = v;
}
for (const f of PLAIN) for (const [name, e] of Object.entries(read(f))) put(name, e, 'value', f);
for (const [file, mode] of Object.entries(THEMES)) {
  const f = `functional/themes/${file}.json`;
  for (const [name, e] of Object.entries(read(f))) put(name, e, mode, f);
}
for (const [name, e] of Object.entries(read('functional/size/size-coarse.json'))) put(name, e, 'coarse', 'size-coarse.json');

const sorted = Object.fromEntries(Object.keys(tokens).sort().map(k => [k, tokens[k]]));
const resolved = {
  $schema: 'schema/resolved.schema.json',
  source: { repo: 'primer/react', commit, package: '@primer/primitives', version },
  modes: Object.fromEntries(Object.entries(THEMES).map(([file, mode]) => [mode, file]).concat([['coarse', 'size-coarse']])),
  units: 'px for dimensions (rem at 16px), {value, unit: "em"} where Primer is relative to the font, ms for durations, cubicBezier as [x1, y1, x2, y2], colours as #rrggbb or #rrggbbaa, shadows as layers of {x, y, blur, spread, color, inset}, typography line heights in px',
  tokens: sorted,
};
const out = JSON.stringify(resolved, null, 1) + '\n';
if (process.argv.includes('--stdout')) { writeSync(1, out); process.exit(0); }
writeFileSync('tokens/primer.resolved.json', out);
const types = {};
for (const t of Object.values(tokens)) types[t.type] = (types[t.type] ?? 0) + 1;
console.log(`${Object.keys(tokens).length} tokens: ${Object.entries(types).map(([k, n]) => `${n} ${k}`).join(', ')}`);
