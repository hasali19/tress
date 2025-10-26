import { Base64 } from "js-base64";

function isArrayEqual(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) {
    return false;
  }

  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }

  return true;
}

export async function subscribeForPushNotifications() {
  const registration = await navigator.serviceWorker.ready;
  const config = await fetch("/api/config").then((res) => res.json());

  let subscription = await registration.pushManager.getSubscription();

  if (subscription) {
    // Decode public key from server to bytes
    const serverPublicKey = Base64.toUint8Array(config.vapid.public_key);
    // Check if the server public key has changed compared to the public key
    // used for the existing subscription
    if (
      !subscription.options.applicationServerKey ||
      !isArrayEqual(
        new Uint8Array(subscription.options.applicationServerKey),
        serverPublicKey,
      )
    ) {
      console.log(
        "Server public key has changed, unsubscribing from push service",
        serverPublicKey,
        subscription.options.applicationServerKey,
      );
      // If the public key has changed, we need to unsubscribe and resubscribe
      await subscription.unsubscribe();
      subscription = null;
    }
  }

  if (!subscription) {
    console.log("Subscribing to push service", config);
    const publicKey = config.vapid.public_key;
    try {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: publicKey,
      });
    } catch (e) {
      console.error(e);
    }
  }

  if (!subscription) {
    console.error("Failed to subscribe to push service");
    return;
  }

  await fetch("/api/push_subscriptions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      subscription: subscription.toJSON(),
      encodings: PushManager.supportedContentEncodings,
    }),
  });
}

export async function unsubscribeFromPushNotifications() {
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.getSubscription();
  if (subscription) {
    await subscription.unsubscribe();
  }
}

export async function getPushSubscriptionStatus() {
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.getSubscription();
  const config = await fetch("/api/config").then((res) => res.json());

  if (subscription) {
    const serverPublicKey = Base64.toUint8Array(config.vapid.public_key);
    if (
      subscription.options.applicationServerKey &&
      isArrayEqual(
        new Uint8Array(subscription.options.applicationServerKey),
        serverPublicKey,
      )
    ) {
      return "subscribed";
    }
  }

  return "unsubscribed";
}
