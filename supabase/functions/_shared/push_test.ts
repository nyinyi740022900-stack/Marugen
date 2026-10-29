import { assertEquals } from "jsr:@std/assert@1";
import { ANDROID_CHANNEL_ID, buildFcmMessage } from "./push.ts";

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
