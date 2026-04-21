/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'selector',
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        // Semantic tokens — rgb so Tailwind opacity modifiers work.
        // Values flip via [data-theme="dark"] CSS variables.
        ink: 'rgb(var(--ink-rgb) / <alpha-value>)',
        milk: 'rgb(var(--milk-rgb) / <alpha-value>)',
        cream: 'rgb(var(--cream-rgb) / <alpha-value>)',
        canvas: 'rgb(var(--canvas-rgb) / <alpha-value>)',
        'surface-warm': 'rgb(var(--surface-warm-rgb) / <alpha-value>)',
        charcoal: 'rgb(var(--charcoal-rgb) / <alpha-value>)',
        silver: 'rgb(var(--silver-rgb) / <alpha-value>)',
        tin: 'rgb(var(--tin-rgb) / <alpha-value>)',

        // Legacy dark tokens (kept for explicit dark usage)
        nightshade: '#1d0d4b',
        'deep-violet': '#3b1f86',

        violet: {
          DEFAULT: '#3b1f86',
          deep: '#1d0d4b',
          hot: '#9d7aff',
          soft: '#c1a9ff',
          fade: '#ff7ad1',
          dust: '#e0d4ff',
        },
        // `accent` is the unified brand color (violet-hot).
        accent: {
          DEFAULT: '#9d7aff',
          soft: '#c1a9ff',
        },
        // Amber is urgency-only (expires <1h, warnings).
        warning: {
          DEFAULT: '#ff9f47',
          soft: '#ffc487',
        },
        amber: {
          DEFAULT: '#ff9f47',
          soft: '#ffc487',
        },
        ember: '#ffc487',
        coral: '#ff4e7c',
      },
      fontFamily: {
        display: [
          '"Bricolage Grotesque"',
          'Söhne',
          'Inter Tight',
          'system-ui',
          '-apple-system',
          'sans-serif',
        ],
        mono: [
          '"JetBrains Mono"',
          'ui-monospace',
          'SFMono-Regular',
          'Menlo',
          'monospace',
        ],
      },
      letterSpacing: {
        tightest: '-0.06em',
        'heading': '-0.045em',
        'heading-lg': '-0.055em',
      },
      fontSize: {
        'hero': ['clamp(56px, 11vw, 180px)', { lineHeight: '0.9', letterSpacing: '-0.055em' }],
        'section': ['clamp(40px, 6vw, 88px)', { lineHeight: '0.95', letterSpacing: '-0.04em' }],
      },
      screens: {
        sm: '640px',
        md: '768px',
        lg: '1024px',
        xl: '1280px',
        '2xl': '1536px',
      },
      transitionTimingFunction: {
        spring: 'cubic-bezier(0.16, 1, 0.3, 1)',
      },
    },
  },
  plugins: [],
};
