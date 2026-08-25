module.exports = {
  plugins: {
    // Tailwind v4 ships as its own PostCSS plugin; nesting and vendor
    // prefixing are handled internally, so tailwindcss/nesting and
    // autoprefixer are no longer part of the chain.
    '@tailwindcss/postcss': {}
  }
}
