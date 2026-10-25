// Read the same importable drafts produced by the native example reproducer.
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";
const [modulePath, output] = process.argv.slice(2);
const { evaluate } = await import(pathToFileURL(resolve(modulePath)));
const { readDraft, invoke } = await import("../browser/workbench.mjs");
for (const id of ["multi", "missing", "technique", "revised"]) {
  const draft = readDraft(await readFile(resolve(output, id, "draft.json"), "utf8"));
  for (const format of ["json", "csv", "markdown", "svg", "html"]) {
    const result = invoke(evaluate, { action: "review", study_json: draft.study_json,
      followup_csv: draft.followup_csv, language: draft.language, format });
    assert.equal(result.ok, true, id);
    const expected = await readFile(resolve(output, id, "report." + (format === "markdown" ? "md" : format)), "utf8");
    assert.equal(result.result.content, expected, `${id}/${format}`);
  }
}
console.log("Example drafts: 4 imported, 20 browser/native format comparisons passed");
