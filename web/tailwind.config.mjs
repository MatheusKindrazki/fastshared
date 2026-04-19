/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        ink: '#070318',
        nightshade: '#1d0d4b',
        violet: {
          DEFAULT: '#3b1f86',
          deep: '#1d0d4b',
          hot: '#9d7aff',
          soft: '#c1a9ff',
          fade: '#ff7ad1',
          dust: '#e0d4ff',
        },
        amber: {
          DEFAULT: '#ff9f47',
          soft: '#ffc487',
        },
        ember: '#ffc487',
        coral: '#ff4e7c',
        cream: '#ffe0b8',
        milk: '#fafaff',
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
