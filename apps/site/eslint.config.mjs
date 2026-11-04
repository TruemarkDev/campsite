import base from '@campsite/eslint-config/flat-base.mjs'
import next from '@campsite/eslint-config/flat-next.mjs'
import restrictedUseInView from '@campsite/eslint-config/rules/restricted-use-in-view.js'

const config = [...base, ...next, restrictedUseInView, { ignores: ['.*.js', '.next/**', 'node_modules/**', 'dist/**'] }]

export default config
