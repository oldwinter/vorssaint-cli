export const title = "Take one camera photo";
export const state = ({s}) => s.phase === "error"
  ? (s.running ? "Process exits before explicit camera stop" : "Camera access refused")
  : ({
    ready: "You select a camera and filename",
    configured: "Permission granted; camera configured",
    waiting: "Camera running; waiting for a frame",
    encoding: "Converting and writing the photo",
    returning: "Photo saved; returning from command",
    done: "Camera explicitly stopped",
  })[s.phase];
export const step = (a) => ({
  Allow: "camera access is granted", Deny: "camera access is denied",
  Start: "the camera starts", ReceiveFrame: "the first frame arrives",
  FrameTimeout: "no frame arrives before the timeout",
  EncodeOrWriteFails: "conversion or disk write fails",
  Save: "the photo is written", ReturnAndDefer: "normal return runs cleanup",
})[a] ?? null;
