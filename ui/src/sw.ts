/// <reference lib="WebWorker" />

declare let self: ServiceWorkerGlobalScope;

self.addEventListener("install", () => {
  console.log("service worker installed");
});

self.addEventListener("push", (e) => {
  e.waitUntil(onPush(e));
});

async function onPush(e: PushEvent) {
  const data = await e.data?.json();

  console.log("push", data);

  const post = await fetch(`/api/posts/${data.id}`).then((res) => res.json());

  await self.registration.showNotification(data.title, {
    body: post.description,
    image: post.thumbnail,
  } as NotificationOptions);
}
