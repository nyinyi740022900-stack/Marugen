import { assertEquals } from "jsr:@std/assert@1";
import { ANDROID_CHANNEL_ID, buildFcmMessage, pushTargets } from "./push.ts";

Deno.test("push rings on both platforms and keeps the real badge", () => {
  const { message } = buildFcmMessage(
    "token-1",
    "Order shipped",
    "Order #42 is on its way.",
    { order_id: "o1", status: "shipped" },
    3,
  );
  assertEquals(message.token, "token-1");
  assertEquals(message.notification, {
    title: "Order shipped",
    body: "Order #42 is on its way.",
  });
  assertEquals(message.android.priority, "HIGH");
  assertEquals(message.android.notification.channel_id, ANDROID_CHANNEL_ID);
  assertEquals(message.android.notification.sound, "default");
  assertEquals(message.apns.payload.aps, { sound: "default", badge: 3 });
  assertEquals(message.apns.headers["apns-priority"], "10");
});

Deno.test("a phone that changed hands only reaches its current account", () => {
  const copy = (userId: string) => ({ userId, title: "t", body: "b" });
  const targets = pushTargets(
    new Map([["a", copy("a")], ["b", copy("b")], ["muted", copy("muted")]]),
    new Set(["a", "b"]),
    [
      { user_id: "b", token: "shared-phone" },
      { user_id: "a", token: "a-tablet" },
      { user_id: "a", token: "a-phone" },
    ],
    [
      { id: "a", fcm_token: "shared-phone" },
      { id: "b", fcm_token: "b-legacy" },
      { id: "muted", fcm_token: "muted-phone" },
    ],
  );
  assertEquals(
    targets.map((t) => `${t.userId}:${t.token}`).sort(),
    ["a:a-phone", "a:a-tablet", "b:b-legacy", "b:shared-phone"],
  );
});
