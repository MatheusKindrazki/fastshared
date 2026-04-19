/**
 * Hero orchestration (v3).
 *
 * The v3 brand mark (PlaneArc) uses a CSS-only stroke-dashoffset animation
 * (see global.css @keyframes arc-draw) so no JS is needed for the mark itself.
 *
 * This script now only wires the Dynamic Island state rotator and respects
 * prefers-reduced-motion by locking to the "completed" resting state.
 */

type El = Element | null;

function mount(): void {
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ----- Dynamic Island state rotator (2s per state) -----
  const island: El = document.querySelector('[data-island-root]');
  if (island && !prefersReducedMotion) {
    const states = island.querySelectorAll<HTMLElement>('.island-state');
    if (states.length > 0) {
      let i = 0;
      states[i]!.classList.add('is-active');
      setInterval(() => {
        states[i]!.classList.remove('is-active');
        i = (i + 1) % states.length;
        states[i]!.classList.add('is-active');
      }, 2000);
    }
  } else if (island && prefersReducedMotion) {
    // Show the "completed" state as the resting frame under reduced motion.
    const completed = island.querySelector<HTMLElement>('[data-state="completed"]');
    completed?.classList.add('is-active');
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount, { once: true });
} else {
  mount();
}
