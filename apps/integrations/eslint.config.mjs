import base from '@campsite/eslint-config/flat-base.mjs'
import next from '@campsite/eslint-config/flat-next.mjs'

const config = [...base, ...next, { ignores: ['.*.js', '.next/**', 'node_modules/**', 'dist/**'] }]

export default config
