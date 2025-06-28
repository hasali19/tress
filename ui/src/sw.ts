/// <reference lib="WebWorker" />

declare let self: ServiceWorkerGlobalScope;

self.addEventListener("install", (e) => {
  console.log("service worker installed");
});

self.addEventListener("push", (e) => {
  e.waitUntil(onPush(e));
});

async function onPush(e: PushEvent) {
  const data = await e.data?.json();

  console.log("push", data);

  await self.registration.showNotification(data.title);
}
