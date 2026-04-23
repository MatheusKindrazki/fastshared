/**
 * Premium scroll orchestration.
 *
 * - IntersectionObserver-driven reveal animations
 * - Nav background blur on scroll
 * - Dynamic Island state rotator (4s interval)
 * - Reduced-motion respected everywhere
 */

type El = Element | null;

function mount(): void {
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ── 1. Scroll reveal ──
  const revealElements = document.querySelectorAll<HTMLElement>('.reveal');
  if (revealElements.length > 0 && !prefersReducedMotion) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: '0px 0px -40px 0px' }
    );
    revealElements.forEach((el) => observer.observe(el));
  } else {
    // If reduced motion, show everything immediately
    revealElements.forEach((el) => el.classList.add('is-visible'));
  }

  // ── 2. Nav blur on scroll ──
  const nav = document.querySelector<HTMLElement>('#main-nav');
  if (nav) {
    let ticking = false;
    const onScroll = () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          if (window.scrollY > 60) {
            nav.classList.add('nav-scrolled');
          } else {
            nav.classList.remove('nav-scrolled');
          }
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  // ── 3. Dynamic Island — rotate through states every 4s ──
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
  }, 4000);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount, { once: true });
} else {
  mount();
}

export {};
