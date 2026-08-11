// @vitejs/plugin-react v5 resolves its types only through the package.json
// "exports" map, which moduleResolution "node" cannot see (and its shipped
// declarations need a newer TypeScript than this repo pins). Declare the
// minimal surface vitest.config.mts uses.
declare module '@vitejs/plugin-react' {
  import type { PluginOption } from 'vite'

  export default function react(options?: Record<string, unknown>): PluginOption
}
