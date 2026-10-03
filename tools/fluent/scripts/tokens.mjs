// tokens.mjs writes tokens/fluent.resolved.json and tokens/fluent.tokens.json
// from the pinned @fluentui/tokens package in upstream/npm (the values apps
// get) and the token sources in upstream/tokens (the alias each value came
// from, read off the generated alias files).
//
//   node scripts/tokens.mjs    (from the kit root; just fluent-kit-tokens)
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, readdirSync, writeSync } from 'node:fs';
const require = createRequire(import.meta.url);
const pkg = require('../upstream/npm/package/lib-commonjs/index.cjs');
const version = JSON.parse(readFileSync('upstream/npm/package/package.json', 'utf8')).version;
const commit = readFileSync('upstream/COMMIT', 'utf8').trim();

const themes = {
  value: pkg.webLightTheme, dark: pkg.webDarkTheme, highContrast: pkg.teamsHighContrastTheme,
  teamsLight: pkg.teamsLightTheme, teamsDark: pkg.teamsDarkTheme,
};
const globalFiles = readdirSync('upstream/tokens/global').filter(f => f.endsWith('.ts'));
const globalNames = new Set();
for (const f of globalFiles) for (const m of readFileSync(`upstream/tokens/global/${f}`, 'utf8').matchAll(/^\s{2}([a-zA-Z0-9]+):/gm)) globalNames.add(m[1]);
for (const s of ['shadow2','shadow4','shadow8','shadow16','shadow28','shadow64']) { globalNames.add(s); globalNames.add(s + 'Brand'); }

// aliases: "colorNeutralForeground1: grey[14]," in the light alias files -> global.grey.14
const alias = {};
for (const f of ['alias/lightColor.ts', 'alias/lightColorPalette.ts']) {
  for (const m of readFileSync(`upstream/tokens/${f}`, 'utf8').matchAll(/^\s{2}([a-zA-Z0-9]+):\s*([a-zA-Z]+)(?:\[(\d+)\]|\.([a-zA-Z0-9]+))?,/gm)) {
    const [, name, ident, idx, key] = m;
    alias[name] = idx !== undefined ? `${ident}.${idx}` : key !== undefined ? `${ident}.${key}` : ident;
  }
}

function classify(name, v) {
  if (/^shadow/.test(name)) return 'shadow';
  if (/^color/.test(name)) return 'color';
  if (/^fontFamily/.test(name)) return 'fontFamily';
  if (/^fontWeight/.test(name)) return 'fontWeight';
  if (/^fontSize|^lineHeight|^spacing|^strokeWidth|^borderRadius/.test(name)) return 'dimension';
  if (/^duration/.test(name)) return 'duration';
  if (/^curve/.test(name)) return 'cubicBezier';
  throw new Error(`unclassified token ${name} = ${v}`);
}
// color normalises every colour to #rrggbb, or #rrggbbaa when it has alpha:
// the sources write white, rgba(0,0,0,0.12) and 'transparent' alike.
function color(v) {
  if (v === 'transparent') return '#00000000';
  const m = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(v);
  if (m) {
    const h = n => Number(n).toString(16).padStart(2, '0');
    const a = m[4] === undefined ? 1 : Number(m[4]);
    return '#' + h(m[1]) + h(m[2]) + h(m[3]) + (a === 1 ? '' : h(Math.round(a * 255)));
  }
  if (/^#[0-9a-fA-F]{6}$/.test(v)) return v.toLowerCase();
  if (/^#[0-9a-fA-F]{8}$/.test(v)) return v.toLowerCase();
  throw new Error(`colour ${v}`);
}
function convert(type, v) {
  switch (type) {
    case 'dimension': { const m = /^(-?[\d.]+)(px)?$/.exec(v); if (!m) throw new Error(`dimension ${v}`); return Number(m[1]); }
    case 'duration': return Number(/^(\d+)ms$/.exec(v)[1]);
    case 'cubicBezier': return /^cubic-bezier\(([^)]+)\)$/.exec(v)[1].split(',').map(Number);
    case 'shadow': return v.split(/,\s*(?=0 )/).map(layer => {
      const m = /^(-?[\d.]+)(?:px)? (-?[\d.]+)(?:px)? (-?[\d.]+)(?:px)? (rgba?\([^)]*\)|#[0-9a-fA-F]+)$/.exec(layer.trim());
      if (!m) throw new Error(`shadow layer ${layer}`);
      return { x: Number(m[1]), y: Number(m[2]), blur: Number(m[3]), color: color(m[4]) };
    });
    case 'color': return color(v);
    case 'fontFamily': case 'fontWeight': return v;
  }
}
const tokens = {};
for (const name of Object.keys(themes.value)) {
  const type = classify(name, themes.value[name]);
  const t = { tier: globalNames.has(name) ? 'global' : 'alias', type, value: convert(type, themes.value[name]) };
  for (const mode of ['dark', 'highContrast', 'teamsLight', 'teamsDark']) {
    const v = convert(type, themes[mode][name]);
    if (JSON.stringify(v) !== JSON.stringify(t.value)) t[mode] = v;
  }
  if (alias[name]) t.alias = `global.${alias[name]}`;
  tokens[`tokens.${name}`] = t;
}
// typography styles: composites over the base tokens
const typography = {};
for (const [name, st] of Object.entries(pkg.typographyStyles)) {
  const ref = k => Object.keys(themes.value).find(n => `var(--${n})` === st[k]);
  typography[`typographyStyles.${name}`] = {
    type: 'typography',
    value: { fontFamily: ref('fontFamily'), fontSize: convert('dimension', themes.value[ref('fontSize')]), fontWeight: themes.value[ref('fontWeight')], lineHeight: convert('dimension', themes.value[ref('lineHeight')]) },
    tokens: { fontFamily: `tokens.${ref('fontFamily')}`, fontSize: `tokens.${ref('fontSize')}`, fontWeight: `tokens.${ref('fontWeight')}`, lineHeight: `tokens.${ref('lineHeight')}` },
  };
}
const resolved = {
  $schema: 'schema/resolved.schema.json',
  source: { repo: 'microsoft/fluentui', commit, package: '@fluentui/tokens', version },
  modes: { value: 'webLightTheme', dark: 'webDarkTheme', highContrast: 'teamsHighContrastTheme', teamsLight: 'teamsLightTheme', teamsDark: 'teamsDarkTheme' },
  units: 'px for dimensions, ms for durations, cubicBezier as [x1, y1, x2, y2], colours as #rrggbb or #rrggbbaa (the source\'s rgba() and transparent normalised), shadows as layers of {x, y, blur, color}',
  tokens: { ...tokens, ...typography },
};
const out = JSON.stringify(resolved, null, 1) + '\n';
if (process.argv.includes('--stdout')) { writeSync(1, out); process.exit(0); }
writeFileSync('tokens/fluent.resolved.json', out);

// DTCG: the same tokens with the alias chain intact where the source shows one.
const dtcg = { $schema: 'https://www.designtokens.org/schema/2025.10.json', $description: `Fluent UI v9 tokens (@fluentui/tokens ${version}); global tokens hold values, alias tokens reference them; per-theme values in $extensions.fluent.modes` };
const dtType = { color: 'color', dimension: 'dimension', duration: 'duration', cubicBezier: 'cubicBezier', fontFamily: 'fontFamily', fontWeight: 'fontWeight', shadow: 'shadow' };
const globalGroup = {}, aliasGroup = {};
for (const [path, t] of Object.entries(tokens)) {
  const name = path.slice('tokens.'.length);
  const entry = { $type: dtType[t.type], $value: t.value };
  if (t.type === 'dimension') entry.$value = { value: t.value, unit: 'px' };
  if (t.type === 'duration') entry.$value = { value: t.value, unit: 'ms' };
  const modes = {};
  for (const m of ['dark', 'highContrast', 'teamsLight', 'teamsDark']) if (t[m] !== undefined) modes[m] = t[m];
  if (Object.keys(modes).length) entry.$extensions = { fluent: { modes } };
  if (t.alias) entry.$extensions = { ...(entry.$extensions ?? {}), fluent: { ...(entry.$extensions?.fluent ?? {}), source: t.alias } };
  (t.tier === 'global' ? globalGroup : aliasGroup)[name] = entry;
}
dtcg.global = globalGroup; dtcg.alias = aliasGroup;
dtcg.typographyStyles = Object.fromEntries(Object.entries(typography).map(([p, t]) => [p.split('.')[1], { $type: 'typography', $value: Object.fromEntries(Object.entries(t.tokens).map(([k, v]) => [k, `{${v.replace('tokens.', 'alias.').replace(/^alias\.(fontFamily|fontSize|fontWeight|lineHeight)/, 'global.$1')}}`])) }]));
writeFileSync('tokens/fluent.tokens.json', JSON.stringify(dtcg, null, 1) + '\n');
const n = Object.keys(tokens).length, g = Object.values(tokens).filter(t => t.tier === 'global').length, a = Object.values(tokens).filter(t => t.alias).length;
console.log(`${n} tokens (${g} global, ${n - g} alias, ${a} with a source), ${Object.keys(typography).length} typography styles`);
