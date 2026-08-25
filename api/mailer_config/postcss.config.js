module.exports = ({ env }) => ({
  plugins: {
    '@tailwindcss/postcss': {
      optimize: env === 'production'
    },
    'postcss-custom-properties': {
      preserve: false
    },
    'postcss-logical': {},
    'postcss-calc': {}
  }
})
