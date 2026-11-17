# Lokal website (GitHub Pages)

This is the shared public website for **Lokal Desktop** and **Lokal Mobile**.

**Repository:** \`lokal-music/mobile\`. The desktop repository's GitHub Pages site remains reserved for Cast.

## Deployment

The site is a static application, intentionally without a framework, package installation or build output:

- \`/index.html\` — page content, metadata, accessible HTML, SEO.
- \`/site/styles.css\` — responsive design and motion; includes reduced-motion and high-contrast handling.
- \`/site/main.js\` — menu, tabs, progressive scroll effects and public release lookups.
- \`/assets/branding/lokal_icon.png\` and \`/docs/images/\` — existing local brand and mobile artwork.
- Desktop preview images load from \`raw.githubusercontent.com/lokal-music/desktop/main/docs/screenshots/\`; no changes to the desktop repo are needed.

**GitHub Pages source:** Settings → Pages → Deploy from a branch → \`main\` → \`/(root)\`.

Once the site PR is merged, Pages publishes \`index.html\` to:

https://lokal-music.github.io/mobile/

If Settings → Pages is configured for **GitHub Actions** rather than branch deployment, change the source to **Deploy from a branch / main / (root)**. This setup deliberately doesn't install a second Pages deployment workflow that might interfere with the existing Pages source.

The site uses relative asset URLs, so it also works at \`/mobile/\` and from other nested path deployments.

## Downloads

The site resolves **latest stable release assets** client-side from GitHub's public API:

- Desktop: \`lokal-music/desktop\` release tag \`desktop\`
- Android: \`lokal-music/mobile\` release tag \`android\`
- iOS: \`lokal-music/mobile\` release tag \`ios\`

The corresponding buttons always point at the permanent GitHub release pages in the HTML. JavaScript upgrades those links to actual asset downloads when the API succeeds. Network failures, GitHub API rate limits, unavailable assets or JavaScript being disabled leave functional release-page links in place.

Supported primary downloads: Windows installer (x64), macOS DMG (Apple Silicon and Intel), Linux AppImage (x64), Android ARM64 APK and iOS IPA. Additional desktop architecture/package formats remain available through the desktop release page.

No build or platform-specific releases run from website edits.

## Local preview and checks

From the mobile repository root:

\`\`\`sh
python3 -m http.server 8000
# Open http://localhost:8000/
node --check site/main.js
node site/check.mjs
\`\`\`

The \`Website checks\` workflow runs the static validation on changes to the website files. For visual QA, check desktop widths (1440, 1280, 1024) and mobile widths (390, 360, 320), both motion settings, keyboard navigation, the mobile navigation menu, tabs, and all release page fallbacks.

## Editorial guidelines

Keep platform claims aligned with the actual product docs, avoid presenting online source availability as guaranteed, and never describe DSP/mixed audio as bit-perfect. Demo screenshots contain fictional library content. Keep primary navigation, release links and core content accessible without scripting. Preserve the desktop Cast Pages deployment.
