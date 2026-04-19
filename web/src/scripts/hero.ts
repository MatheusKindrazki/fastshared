/**
 * Lean client-side hero orchestration.
 *
 * The Plane + Arc (Refined) hero animation is pure CSS (see global.css,
 * `[data-animate="planearc"]` selectors). Reduced-motion is also handled
 * there. This file only wires the Dynamic Island state rotator used
 * further down the page.
 */

type El = Element | null;

function mount(): void {
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Dynamic Island — rotate through the three states every 2s.
  const island: El = document.querySelector('[data-island-root]');
  if (!island) return;

  const states = island.querySelectorAll<HTMLElement>('.island-state');
  if (states.length === 0) return;

  if (prefersReducedMotion) {
    const completed = island.querySelector<HTMLElement>('[data-state="completed"]');
    completed?.classList.add('is-active');
    return;
  }

  let i = 0;
  states[i]!.classList.add('is-active');
  window.setInterval(() => {
    states[i]!.classList.remove('is-active');
    i = (i + 1) % states.length;
    states[i]!.classList.add('is-active');
  }, 2000);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount, { once: true });
} else {
  mount();
}

export {};
