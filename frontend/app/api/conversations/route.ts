import { backendRequest, parseJsonSafe } from "@/lib/backend";

export async function GET(request: Request) {
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return Response.json({ error: "Missing authorization token." }, { status: 401 });
  }

  const url = new URL(request.url);
  const limit = url.searchParams.get("limit");
  const query = limit ? `?limit=${encodeURIComponent(limit)}` : "";

  try {
    const backendResponse = await backendRequest(`/conversations/me${query}`, {
      method: "GET",
      headers: {
        Authorization: authorization,
      },
    });

    const payload = await parseJsonSafe(backendResponse);
    return Response.json(payload, { status: backendResponse.status });
  } catch {
    return Response.json(
      { error: "Unable to fetch conversation history." },
      { status: 502 },
    );
  }
}
