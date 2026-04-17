/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'media',
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // 媽祖廟五色
        mazu: {
          cyan:   '#8FADBF',  // 青灰 — links, h3
          gold:   '#F2D479',  // 金黃 — code, active
          orange: '#F28D35',  // 橘 — accent, CTA
          deep:   '#F27B35',  // 深橘 — borders
          red:    '#F24130',  // 朱紅 — warnings
        },
        // Light palette
        paper: {
          50:  '#fdfcf9',
          100: '#f7f5ef',
          200: '#edeadf',
          300: '#ddd8ca',
          400: '#c4bda8',
        },
        // Dark palette
        abyss: {
          950: '#08080e',
          900: '#0e0e18',
          850: '#131320',
          800: '#1a1a2c',
          700: '#252540',
          600: '#333358',
        },
        // Text
        ink: {
          50:  '#f0f0f4',
          100: '#dddde4',
          200: '#c0c0cc',
          300: '#9898ac',
          400: '#70708a',
          500: '#555570',
          600: '#404058',
          700: '#303048',
          800: '#222238',
          900: '#161628',
        },
      },
      fontFamily: {
        sans: [
          '-apple-system', 'BlinkMacSystemFont',
          '"Noto Sans TC"', '"PingFang TC"',
          '"Segoe UI"', 'Roboto', 'sans-serif',
        ],
        mono: [
          '"SF Mono"', 'Menlo', 'Monaco',
          '"Cascadia Code"', 'Consolas', 'monospace',
        ],
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
};
