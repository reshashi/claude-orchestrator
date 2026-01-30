import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    exclude: ['node_modules', 'dist'],
    environment: 'node',
    globals: false,
    // Prevent vitest from looking for config in parent directories
    root: '.',
  },
  // Disable CSS processing since we don't need it
  css: {
    postcss: {},
  },
});
