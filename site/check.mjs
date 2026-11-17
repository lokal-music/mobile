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
// Header social links must remain accessible and use the invite shared by both apps.
const navActions = html.split('<div class="nav-actions">')[1]?.split('</div>')[0] ?? '';
assert.match(navActions, /class="social-link github-link"/, 'GitHub header link is missing');
assert.match(navActions, /viewBox="-1 -1 18 18"/, 'GitHub logo should have breathing room and avoid clipping');
assert.match(navActions, /class="social-link discord-link"/, 'Discord header link is missing');
assert.match(navActions, /aria-label="Join Lokal Music on Discord"/, 'Discord icon needs an accessible label');
assert.ok(navActions.includes('https://discord.com/invite/8bUGWChwpG'), 'Header must use the app Discord invite');
assert.match(css, /\.social-link svg \{[^}]*overflow:\s*visible/, 'Social icon SVGs should not clip');
assert.match(css, /prefers-reduced-motion:\s*reduce/, 'Reduced-motion styles missing');
assert.match(css, /:focus-visible/, 'Visible keyboard focus styles missing');
assert.match(js, /IntersectionObserver/, 'Progressive reveal handler missing');
assert.match(js, /controller\.abort/, 'Release API timeout missing');

console.log('Lokal website static checks passed.');
