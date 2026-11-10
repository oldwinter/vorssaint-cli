export const title = "Install or replace an app from a disk image";
export const state = ({s}) => {
  if (s.reportedRemoved && s.source)
    return s.mounted ? "Reports image removed; original image remains mounted" : "Reports image removed; original image still exists";
  if (s.phase === "error")
    return !s.oldApp ? "Copy failed; previous app lost; image mounted"
      : s.mounted ? "Command exits with the image still mounted" : "Image could not be mounted";
  if (s.phase === "done") return s.mounted ? "Install reported; detach failed" : "App installed; image ejected";
  return ({
    ready: "You choose a disk image",
    mounted: "Image mounted read-only",
    confirming: "Waiting for install approval",
    replacing: "Approved; replacing the existing app",
    copying: "Previous app deleted; copying the replacement",
    copied: "New app copied",
    returning: "Install reported; preparing to eject",
  })[s.phase];
};
export const step = (a) => ({
  AttachFails: "mount fails", Mount: "mount the image",
  NoApp: "the image contains no app", FindApp: "an app is found",
  Decline: "you decline or --yes is missing without a terminal",
  Confirm: "you approve the installation", RemoveOld: "delete the old app",
  CopyFails: "copying the replacement fails", Copy: "copy the replacement",
  KeepImage: "keep the input image", Cleanup: "delete the input image",
  CleanupFails: "input-image deletion fails silently",
  Detach: "normal return ejects the image", DetachFails: "eject fails silently",
})[a] ?? null;
