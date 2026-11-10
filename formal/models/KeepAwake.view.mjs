export const title = "Keep the Mac awake until work finishes";
export const state = ({s}) => {
  if (s.phase === "awake") return ({
    forever: "Sleep prevention active until Ctrl-C",
    duration: "Sleep prevention active until the deadline",
    pid: "Sleep prevention active while the PID is alive",
  })[s.mode];
  if (s.phase === "interrupt-pending") return ({
    forever: "Ctrl-C queued; indefinite assertion remains active",
    duration: "Ctrl-C queued; deadline still applies",
    pid: "Ctrl-C queued; watched PID still applies",
  })[s.mode];
  return ({
  ready: "You start keep-awake",
  returning: "Duration ended or watched process disappeared",
  done: "Command finished; assertion released",
  })[s.phase];
};
export const step = (a) => ({
  AcquireFails: "macOS rejects the assertion", Acquire: "macOS grants the assertion",
  DurationExpires: "the requested duration ends", WatchedPIDExits: "the watched PID disappears",
  PressCtrlC: "you press Ctrl-C", SleepAgain: "the loop sleeps again",
  ReturnAndRelease: "normal return releases the assertion",
})[a] ?? null;
