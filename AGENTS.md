# Development guide

This is a MoonBit library with a native demonstration CLI.

- Keep public domain types in the `lesion`, `visit`, and `evidence` packages;
  the root package is the supported facade for consumers.
- Keep file access in the CLI. The library evaluates in-memory values.
- Separate structural input errors from not-evaluable clinical observations.
- Use tenths of a millimetre and exact integer threshold comparisons.
- Add tests for medical rule changes and document their primary source and limits.
- Use `///|` blocks, `moon fmt`, and compiler-generated interfaces (`moon info`).
- Run `python scripts/acceptance.py` before delivery. Do not update expected
  clinical categories just to make a failing test pass.
- Keep examples synthetic. Documentation must identify target-only results and
  must not imply overall response, treatment advice, or clinical validation.
