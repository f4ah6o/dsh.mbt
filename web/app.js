async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  try {
    await navigator.serviceWorker.register("/sw.js", { scope: "/" });
  } catch {
    // The app remains usable without installation or an offline shell.
  }
}

async function hasVersionedApi() {
  try {
    const response = await fetch("/api/v1/snapshot", {
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    return response.status !== 404 && response.status !== 405;
  } catch {
    return true;
  }
}

registerServiceWorker();
if (await hasVersionedApi()) {
  await import("./remote-app.js");
} else {
  document.querySelector(".account-bar")?.setAttribute("hidden", "");
  await import("./legacy-app.js");
}
