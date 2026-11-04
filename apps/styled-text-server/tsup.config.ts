import { defineConfig, type Options } from 'tsup'

export default defineConfig((options: Options) => ({
  entryPoints: ['src/index.ts'],
  clean: true,
  // tsup 8.5.1 vendors rollup-plugin-dts 6.1.1, which reads a TypeScript
  // internal (useCaseSensitiveFileNames) that TypeScript 7 removed, so its
  // declaration step crashes. Declarations are emitted by tsc instead.
  dts: false,
  format: ['esm'],
  ...options
}))
