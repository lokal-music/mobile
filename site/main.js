/**
 * Lokal website.
 * Static-first, no dependencies: GitHub Pages can serve the site directly from main.
 * All essential content and release-page fallbacks work without JavaScript.
 */
const doc = document;
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');

function selectFromGroup(buttons, target, attribute, update) {
  buttons.forEach((button) => {
    const selected = button.getAttribute(attribute) === target;
    button.classList.toggle('is-active', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
  update(target);
}

const platformButtons = Array.from(doc.querySelectorAll('[data-platform]'));
const platformNames = ['desktop', 'android', 'ios'];
function choosePlatform(platform) {
  if (!platformNames.includes(platform)) return;
  selectFromGroup(platformButtons, platform, 'data-platform', (key) => {
    platformNames.forEach((name) => {
      const panel = doc.getElementById('download-' + name);
      if (panel) panel.hidden = key !== name;
    });
  });
}

const showcaseButtons = Array.from(doc.querySelectorAll('[data-showcase]'));
function chooseShowcase(key) {
  if (!['desktop', 'mobile'].includes(key)) return;
  selectFromGroup(showcaseButtons, key, 'data-showcase', (target) => {
    const desktop = doc.getElementById('showcase-desktop');
    const mobile = doc.getElementById('showcase-mobile');
    if (desktop) desktop.hidden = target !== 'desktop';
    if (mobile) mobile.hidden = target !== 'mobile';
  });
}

platformButtons.forEach((button) => button.addEventListener('click', () => choosePlatform(button.dataset.platform)));
showcaseButtons.forEach((button) => button.addEventListener('click', () => chooseShowcase(button.dataset.showcase)));
doc.querySelectorAll('[data-choose-platform]').forEach((link) => {
  link.addEventListener('click', () => choosePlatform(link.dataset.choosePlatform));
});

const userAgent = navigator.userAgent || '';
function defaultPlatform() {
  if (/iphone|ipad|ipod/i.test(userAgent)) return 'ios';
  if (/android/i.test(userAgent)) return 'android';
  return 'desktop';
}
choosePlatform(defaultPlatform());

const menuButton = doc.getElementById('menu-toggle');
const nav = doc.getElementById('primary-nav');
function closeMenu() {
  if (!menuButton || !nav) return;
  menuButton.setAttribute('aria-expanded', 'false');
  menuButton.setAttribute('aria-label', 'Open menu');
  nav.classList.remove('is-open');
}
if (menuButton && nav) {
  menuButton.addEventListener('click', () => {
    const opening = menuButton.getAttribute('aria-expanded') !== 'true';
    menuButton.setAttribute('aria-expanded', String(opening));
    menuButton.setAttribute('aria-label', opening ? 'Close menu' : 'Open menu');
    nav.classList.toggle('is-open', opening);
  });
  nav.querySelectorAll('a').forEach((link) => link.addEventListener('click', closeMenu));
  doc.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {
      closeMenu();
      menuButton.focus();
    }
  });
  doc.addEventListener('click', (event) => {
    if (!nav.contains(event.target) && !menuButton.contains(event.target)) closeMenu();
  });
}

const year = doc.getElementById('copyright-year');
if (year) year.textContent = String(new Date().getFullYear());

// Reveal motion is optional. Never hide content without an observer ready to reveal it.
if (!reducedMotion.matches && 'IntersectionObserver' in window) {
  const revealElements = Array.from(doc.querySelectorAll('.reveal'));
  const revealObserver = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    }
  }, { rootMargin: '0px 0px -45px 0px', threshold: 0.06 });
  doc.documentElement.classList.add('js');
  revealElements.forEach((element) => revealObserver.observe(element));
  // The document might be restored from bfcache halfway down the page.
  window.addEventListener('pageshow', () => {
    for (const element of revealElements) {
      const rect = element.getBoundingClientRect();
      if (rect.top < window.innerHeight && rect.bottom > 0) element.classList.add('is-visible');
    }
  });
}

const progress = doc.getElementById('scroll-progress');
let scrollQueued = false;
function updateProgress() {
  scrollQueued = false;
  if (!progress) return;
  const available = doc.documentElement.scrollHeight - window.innerHeight;
  const value = available <= 0 ? 0 : Math.max(0, Math.min(1, window.scrollY / available));
  progress.style.transform = 'scaleX(' + value + ')';
}
window.addEventListener('scroll', () => {
  if (!scrollQueued) {
    scrollQueued = true;
    window.requestAnimationFrame(updateProgress);
  }
}, { passive: true });
window.addEventListener('resize', updateProgress, { passive: true });
updateProgress();

// Mouse-follow lighting is decorative and disabled for coarse pointers / reduced motion.
const hero = doc.querySelector('.hero');
const heroArt = doc.getElementById('hero-art');
if (hero && heroArt && finePointer.matches && !reducedMotion.matches) {
  let pointerQueued = false;
  let nextX = 0;
  let nextY = 0;
  hero.addEventListener('pointermove', (event) => {
    if (event.pointerType !== 'mouse') return;
    const rect = hero.getBoundingClientRect();
    nextX = (event.clientX - rect.left) / rect.width;
    nextY = (event.clientY - rect.top) / rect.height;
    if (!pointerQueued) {
      pointerQueued = true;
      window.requestAnimationFrame(() => {
        pointerQueued = false;
        hero.style.setProperty('--pointer-x', String(nextX * 100) + '%');
        hero.style.setProperty('--pointer-y', String(nextY * 100) + '%');
        // Use tiny adjustments only; the visual must stay easy to read.
        if (window.innerWidth > 1300) {
          heroArt.style.setProperty('--art-x', String((nextX - 0.5) * -11) + 'px');
          heroArt.style.setProperty('--art-y', String((nextY - 0.5) * -8) + 'px');
        }
      });
    }
  }, { passive: true });
  hero.addEventListener('pointerleave', () => {
    hero.style.removeProperty('--pointer-x');
    hero.style.removeProperty('--pointer-y');
    heroArt.style.removeProperty('--art-x');
    heroArt.style.removeProperty('--art-y');
  });
}

// Public GitHub releases have stable per-platform tags. Resolve asset URLs at view time,
// so the website continues downloading the newest builds without manual version edits.
const releases = [
  { key: 'desktop', owner: 'lokal-music', repo: 'desktop', tag: 'desktop' },
  { key: 'android', owner: 'lokal-music', repo: 'mobile', tag: 'android' },
  { key: 'ios', owner: 'lokal-music', repo: 'mobile', tag: 'ios' }
];

const assetMatches = {
  win: (name) => /^Lokal-Setup-.+\.exe$/i.test(name),
  'mac-arm': (name) => /^Lokal-.+-arm64\.dmg$/i.test(name),
  'mac-intel': (name) => /^Lokal-(?!.*arm64).+\.dmg$/i.test(name),
  linux: (name) => /^Lokal-(?!.*arm64).+\.AppImage$/i.test(name),
  android: (name) => /^Lokal-.+-arm64\.apk$/i.test(name),
  ios: (name) => /^Lokal\.ipa$/i.test(name)
};
const releaseAssetKeys = {
  desktop: ['win', 'mac-arm', 'mac-intel', 'linux'],
  android: ['android'],
  ios: ['ios']
};

function applyRelease(release, config) {
  if (!release || release.draft || release.prerelease) return;
  const label = doc.querySelector('[data-release-label="' + config.key + '"]');
  if (label && typeof release.name === 'string') {
    const cleaned = release.name.trim().slice(0, 65);
    if (cleaned) label.textContent = cleaned;
  }

  const assets = Array.isArray(release.assets) ? release.assets : [];
  for (const assetKey of releaseAssetKeys[config.key]) {
    const element = doc.querySelector('[data-asset="' + assetKey + '"]');
    if (!element) continue;
    const match = assets.find((asset) =>
      asset && typeof asset.name === 'string' &&
      typeof asset.browser_download_url === 'string' &&
      assetMatches[assetKey](asset.name)
    );
    if (!match) continue;
    try {
      const url = new URL(match.browser_download_url);
      if (url.protocol !== 'https:' || url.hostname !== 'github.com') continue;
      if (!url.pathname.startsWith('/lokal-music/')) continue;
      element.href = url.href;
      element.title = 'Download ' + match.name;
    } catch {
      // Keep the permanent GitHub release-page fallback.
    }
  }
}

async function loadRelease(config) {
  const url = 'https://api.github.com/repos/' + config.owner + '/' + config.repo + '/releases/tags/' + config.tag;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(url, {
      headers: { Accept: 'application/vnd.github+json' },
      signal: controller.signal,
      cache: 'no-store'
    });
    if (!response.ok) return;
    const payload = await response.json();
    applyRelease(payload, config);
  } catch {
    // Network errors, API limits and blockers must never break download navigation.
  } finally {
    window.clearTimeout(timeout);
  }
}
releases.forEach(loadRelease);
