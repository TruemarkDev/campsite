import base from '@campsite/eslint-config/flat-base.mjs'
import react from '@campsite/eslint-config/flat-react-internal.mjs'

export default [...base, ...react, { ignores: ['.*.js', 'dist/**', 'node_modules/**'] }]
