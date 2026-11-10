export const title = "Record a screen video";
export const state = ({s}) => {
  if (s.lateAppend) return "A late frame reaches the finished writer";
  if (s.phase === "recording")
    return s.failed ? "Capture failed; waiting to stop" : s.frames ? "Recording frames" : "Waiting for the first frame";
  if (s.phase === "drained") return s.stopped ? "Capture stopped" : "Stop timed out; capture may still be live";
  return ({
    ready: "You choose a display and output",
    stopping: "Stopping capture",
    finalized: "Writer finalized",
    saved: "Video saved",
    error: "Command reports an error",
  })[s.phase];
};
export const step = (action) => ({
  Start: "permission granted; capture starts", PermissionDenied: "screen permission denied",
  Frame: "a frame arrives", StreamError: "capture reports a failure",
  RequestStop: "duration ends or you press Ctrl-C",
  StopAcknowledged: "capture confirms it stopped", StopTimesOut: "stop waits ten seconds and times out",
  FinishWriter: "the video writer finalizes",
  LateFrame: "an unacknowledged callback arrives [after a captured frame]",
  Publish: "the command checks frames and failure",
})[action] ?? null;
export const group = ({s}) => s.lateAppend ? "bug" : s.phase === "saved" ? "success" : "active";
export const colors = {active: "blue", success: "teal", bug: "pink"};
