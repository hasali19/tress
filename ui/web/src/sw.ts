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
  const feed = await fetch(`/api/feeds/${post.feed_id}`).then((res) =>
    res.json(),
  );

  await self.registration.showNotification(data.title, {
    body: feed.title,
    image: post.thumbnail,
    data: {
      url: post.url,
    },
  } as NotificationOptions);
}

self.addEventListener("notificationclick", (e) => {
  e.notification.close();

  e.waitUntil(
    self.clients.matchAll({ type: "window" }).then((clients) => {
      for (const client of clients) {
        if (client.url === e.notification.data.url && "focus" in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(e.notification.data.url);
      }
    }),
  );
});
