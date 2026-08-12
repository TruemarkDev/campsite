import base from '@campsite/eslint-config/flat-base.mjs'

export default [...base, { ignores: ['.*.js', 'dist/**', 'node_modules/**'] }]
