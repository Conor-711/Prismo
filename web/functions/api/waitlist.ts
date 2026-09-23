import { handleWaitlist, type WaitlistEnvironment } from "../../server/waitlist/handler";

export function onRequest(context: { request: Request; env: WaitlistEnvironment }): Promise<Response> {
  return handleWaitlist(context.request, context.env);
}
