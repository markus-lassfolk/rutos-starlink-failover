module.exports = {
  "env": {
    "browser": true,
    "es2020": true,
    "node": false
  },
  "extends": ["eslint:recommended"],
  "globals": {
    "L": "readonly",
    "uci": "readonly",
    "rpc": "readonly",
    "session": "readonly",
    "baseURL": "readonly",
    "requestURL": "readonly",
    "location": "readonly",
    "XHR": "readonly",
    "Poll": "readonly",
    "Class": "readonly",
    "Headers": "readonly",
    "Request": "readonly",
    "Response": "readonly"
  },
  "parserOptions": {
    "ecmaVersion": 2020,
    "sourceType": "script"
  },
  "rules": {
    "indent": ["error", 2],
    "linebreak-style": ["error", "unix"],
    "quotes": ["error", "single"],
    "semi": ["error", "always"],
    "no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
    "no-console": "warn",
    "no-debugger": "error",
    "no-trailing-spaces": "error",
    "eol-last": "error",
    "comma-dangle": ["error", "never"],
    "space-before-function-paren": ["error", "never"],
    "keyword-spacing": "error",
    "space-infix-ops": "error",
    "object-curly-spacing": ["error", "never"],
    "array-bracket-spacing": ["error", "never"],
    "computed-property-spacing": ["error", "never"],
    "space-in-parens": ["error", "never"],
    "space-before-blocks": "error",
    "brace-style": ["error", "stroustrup", { "allowSingleLine": true }],
    "curly": ["error", "all"],
    "max-len": ["warn", { "code": 120, "tabWidth": 2 }],
    "camelcase": ["error", { "properties": "never" }],
    "new-cap": "error",
    "no-mixed-spaces-and-tabs": "error",
    "no-multiple-empty-lines": ["error", { "max": 2 }],
    "no-var": "error",
    "prefer-const": "error",
    "arrow-spacing": "error"
  },
  "overrides": [
    {
      "files": ["*.luci.js", "**/luci/**/*.js"],
      "globals": {
        "_": "readonly",
        "N_": "readonly",
        "E": "readonly"
      }
    }
  ]
};
