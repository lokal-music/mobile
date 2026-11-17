import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(resolve(root, 'index.html'), 'utf8');
const css = readFileSync(resolve(root, 'site/styles.css'), 'utf8');
const js = readFileSync(resolve(root, 'site/main.js'), 'utf8');

assert.match(html, /<!doctype html>/i, 'HTML document should be standards mode');
assert.match(html, /<html lang="en">/, 'Document must specify its language');
assert.match(html, /name="description"/, 'Search summary is missing');
assert.match(html, /rel="canonical"/, 'Canonical URL is missing');
assert.match(html, /id="main"/, 'Skip link target is missing');
assert.match(html, /aria-label="Primary navigation"/, 'Accessible navigation is missing');

for (const id of ['experience','features','platforms','about','download','download-desktop','download-android','download-ios','showcase-desktop','showcase-mobile']) {
  assert.ok(html.includes('id="' + id + '"'), 'Missing section: ' + id);
}
for (const fragment of html.matchAll(/href="#([^"]+)"/g)) {
  assert.ok(html.includes('id="' + fragment[1] + '"'), 'Broken hash link: #' + fragment[1]);
}
for (const [_, source] of html.matchAll(/(?:src|href)="(\.\/[^"]+)"/g)) {
  const pathname = source.split(/[?#]/, 1)[0];
  assert.ok(existsSync(resolve(root, pathname)), 'Missing local asset: ' + pathname);
}
for (const image of html.match(/<img\b[^>]*>/g) || []) {
  assert.match(image, /\balt="/, 'Image is missing an alt attribute');
}
for (const key of ['desktop','android','ios']) {
  assert.ok(html.includes('data-platform="' + key + '"'), 'Platform tab missing: ' + key);
  assert.ok(js.includes("key: '" + key + "'"), 'Release lookup missing: ' + key);
}
for (const link of [
  'https://github.com/lokal-music/desktop/releases/tag/desktop',
  'https://github.com/lokal-music/mobile/releases/tag/android',
  'https://github.com/lokal-music/mobile/releases/tag/ios'
]) {
  assert.ok(html.includes(link), 'Stable fallback missing: ' + link);
}
assert.match(css, /prefers-reduced-motion:\s*reduce/, 'Reduced-motion styles missing');
assert.match(css, /:focus-visible/, 'Visible keyboard focus styles missing');
assert.match(js, /IntersectionObserver/, 'Progressive reveal handler missing');
assert.match(js, /controller\.abort/, 'Release API timeout missing');

console.log('Lokal website static checks passed.');
