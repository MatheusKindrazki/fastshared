/**
 * Hero animation orchestration.
 * Re-uses the brand/preview.html temporal-link arc metaphor:
 *   1. origin sphere scales 0 -> 1 with a spring
 *   2. arc draws itself (stroke-dashoffset -> 0)
 *   3. ghost node + particles stagger in with a tiny y-drift
 *
 * Honors prefers-reduced-motion: renders the static end state.
 * Runs once when the hero enters the viewport (IntersectionObserver).
 */

import { gsap } from 'gsap';

type El = Element | null;

function runHeroAnimation(root: Element): void {
  const sphere = root.querySelector<SVGElement>('.js-sphere');
  const ghost = root.querySelector<SVGElement>('.js-ghost');
  const arcs = root.querySelectorAll<SVGPathElement>('.js-arc');
  const particles = root.querySelectorAll<SVGElement>('.js-particle');

  // If any element is missing, bail gracefully — content is already visible via CSS fallback.
  if (!sphere || !ghost || arcs.length === 0) return;

  const tl = gsap.timeline({ defaults: { ease: 'power3.out' } });

  tl.set(sphere, { transformOrigin: '300px 580px' })
    .to(sphere, { opacity: 1, scale: 1, duration: 0.8, ease: 'back.out(1.4)' }, 0)
    .fromTo(
      sphere,
      { scale: 0 },
      { scale: 1, duration: 0.9, ease: 'back.out(1.6)' },
      0,
    )
    .to(
      arcs,
      { strokeDashoffset: 0, duration: 1.6, ease: 'power2.inOut' },
      0.25,
    )
    .to(ghost, { opacity: 1, duration: 0.5 }, 0.9)
    .fromTo(
      particles,
      { opacity: 0, y: 6 },
      {
        opacity: (_i: number, el: Element) => {
          const attr = (el as SVGElement).getAttribute('data-opacity');
          return attr ? parseFloat(attr) : 0.6;
        },
        y: 0,
        duration: 0.55,
        stagger: 0.08,
        ease: 'power2.out',
      },
      1.0,
    );
}

function mount(): void {
  const root = document.querySelector<HTMLElement>('[data-hero-root]');
  if (!root) return;

  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (prefersReducedMotion) {
    // Static end state is already rendered via CSS. Nothing to animate.
    return;
  }

  // Fire once on enter — no re-animations on scroll.
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          runHeroAnimation(entry.target);
          observer.disconnect();
          break;
        }
      }
    },
    { threshold: 0.2 },
  );

  observer.observe(root);

  // ----- Dynamic Island state rotator (6s total, 2s per state) -----
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
