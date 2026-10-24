/** Pure synchronous boundary. JSON input/output contract: docs/browser-adapter.md. */
export declare function evaluate(request_json: string): string;

export type ReportFormat = "json" | "csv" | "markdown" | "svg" | "html";
export type BrowserRequest =
  | { schema_version: 1; action: "review"; study_json: string; followup_csv: string;
      language?: "en" | "zh-CN"; format?: ReportFormat }
  | { schema_version: 1; action: "preflight"; study_json: string; followup_csv: string;
      language?: "en" | "zh-CN"; format?: "json" | "markdown" }
  | { schema_version: 1; action: "template"; template?: "single" | "multi";
      language?: "en" | "zh-CN" };

export interface ReviewNotice {
  code: string; message: string; source: string; field: string | null;
  line: number | null; column: number | null;
  visit_id: string | null; lesion_id: string | null;
}
export interface Preflight {
  schema_version: 1; scope: "input_quality_and_review_hints"; valid: boolean;
  visit_count: number; diagnostics: ReviewNotice[]; input_issues: ReviewNotice[];
  review_hints: ReviewNotice[];
}
export interface ReportResult { format: ReportFormat; media_type: string; content: string }
export interface TemplateResult { files: { name: string; content: string }[] }
interface Envelope { schema_version: 1; scope: "target_lesions_only" }
export type BrowserResponse = Envelope & (
  | { ok: false; action: null; error_kind: "request";
      diagnostics: { code: string; field: string; message: string }[];
      preflight: null; result: null }
  | { ok: false; action: "review" | "preflight"; error_kind: "input";
      diagnostics: []; preflight: Preflight; result: null }
  | { ok: true; action: "review" | "preflight"; error_kind: null;
      diagnostics: []; preflight: Preflight; result: ReportResult }
  | { ok: true; action: "template"; error_kind: null;
      diagnostics: []; preflight: null; result: TemplateResult }
);
