import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    files: ["src/**/*.ts"],
    extends: [tseslint.configs.recommended],
    rules: {
      // Allow TypeScript conventions
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
  {
    ignores: ["dist/", "node_modules/"],
  },
);
