export const title = "Enter and leave the terminal dashboard";
export const state = ({s}) => ({
  ready: "You open the dashboard or app switcher",
  snapshot: "Original terminal settings saved",
  raw: "Keyboard input in raw mode",
  active: "Dashboard visible; cursor hidden",
  restoring: "Restoring terminal settings and cursor",
  done: "Your terminal is usable again",
})[s.phase];
export const step = (a) => ({
  PipeOutput: "output is piped; print one frame",
  SaveTermios: "save the terminal settings", EnterRaw: "enable raw keyboard input",
  ShowDashboard: "enter the alternate screen",
  Quit: "you press q, Escape, or keyboard Ctrl-C",
  FatalSignal: "a handled fatal signal interrupts the app",
  Restore: "restore the saved terminal and cursor", RestoreAgain: "later cleanup is a no-op",
})[a] ?? null;
