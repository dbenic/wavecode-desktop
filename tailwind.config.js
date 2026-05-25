/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      colors: {
        // Match WaveCode core / OG-card palette
        wave: {
          bg: '#0f172a',       // slate-900
          terminal: '#020617', // slate-950
          accent: '#10b981',   // emerald-500
          working: '#10b981',
          idle: '#475569',     // slate-600
          warn: '#f59e0b',     // amber-500
          error: '#ef4444',    // red-500
        },
      },
    },
  },
  plugins: [],
};
