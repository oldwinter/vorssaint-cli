export const title = "Set and verify a fan target";
export const state = ({s}) => s.phase === "error"
  ? s.forced ? "Error reported; manual mode remains set" : "Write refused or unsupported"
  : ({
    ready: "You choose an in-range target",
    confirmed: "You approve the hardware write",
    forced: s.forced ? "Manual mode enabled" : "Forced-bit support unavailable",
    readback: "Target written; verifying readback",
    done: "Matching target confirmed",
  })[s.phase];
export const step = (a) => ({
  Decline: "you decline or --yes is missing without a terminal",
  Confirm: "you approve", ForceMode: "set the manual-control bit",
  ForcedBitAbsent: "the forced bit is unsupported",
  WriteFails: "the target cannot be written", WriteAccepted: "the driver accepts the target",
  ReadMatches: "readback matches within two RPM", ReadMissing: "readback fails",
  ReadMismatch: "firmware reports a different target",
})[a] ?? null;
