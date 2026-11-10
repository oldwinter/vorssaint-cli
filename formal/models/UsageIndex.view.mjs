export const title = "Read and refresh local agent usage";
export const state = ({s}) => ({
  empty: "No cached usage for this transcript",
  cached: "First complete usage record cached",
  appended: "Appended cumulative usage is counted twice",
  partial: "Incomplete last line retained for next scan",
  completed: "Completed line counted once",
  rescanned: "Full reindex restores the correct maximum",
})[s.phase];
export const step = (a) => ({
  ReadFirst: "read the first complete record", ReuseUnchanged: "reuse an unchanged file",
  AppendCumulative: "tail-parse a new cumulative Codex record",
  PartialLine: "a transcript ends partway through a line",
  CompletePartial: "the writer completes that line", Reindex: "you pass --reindex",
})[a] ?? null;
