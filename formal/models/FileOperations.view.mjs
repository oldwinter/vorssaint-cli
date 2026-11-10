export const title = "Preview and apply file operations";
export const state = ({s}) => ({
  planned: s.dry ? "You request a dry run" : "Items selected for removal",
  preview: "Preview shown; files unchanged",
  confirming: "Waiting for confirmation",
  applying: "Moving selected items to Trash",
  aborted: "Cancelled; files unchanged",
  reported: s.failed.length ? "Partial result with failures" : "All selected items moved",
})[s.phase];
export const step = (a) => ({
  Preview: "show the dry-run plan", Ask: "request approval",
  Confirm: "you pass --yes or approve in a terminal",
  DeclineOrNoTTY: "you decline or no interactive input is available",
  Move: "an item moves successfully", MoveFails: "an item cannot be moved",
  Report: "report successful and failed items",
})[a] ?? null;
export const group = ({s}) => s.phase === "preview" || s.phase === "reported" ? "complete" : "active";
export const colors = {complete: "teal", active: "blue"};
