import { backendRequest, parseJsonSafe } from "@/lib/backend";

export async function POST(request: Request) {
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return Response.json({ error: "Missing authorization token." }, { status: 401 });
  }

  try {
    const streamRequested =
      new URL(request.url).searchParams.get("stream") === "true";
    const body = await request.json();
    const backendPath = streamRequested ? "/chat?stream=true" : "/chat";
    const backendResponse = await backendRequest(backendPath, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify(body),
    });

    if (streamRequested) {
      if (!backendResponse.ok) {
        const payload = await parseJsonSafe(backendResponse);
        return Response.json(payload, { status: backendResponse.status });
      }

      return new Response(backendResponse.body, {
        status: backendResponse.status,
        headers: {
          "Content-Type": backendResponse.headers.get("content-type") ?? "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    }

    const payload = await parseJsonSafe(backendResponse);
    return Response.json(payload, { status: backendResponse.status });
  } catch {
    return Response.json(
      { error: "Unable to reach backend chat service." },
      { status: 502 },
    );
  }
}
