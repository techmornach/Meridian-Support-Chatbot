import { backendRequest, parseJsonSafe } from "@/lib/backend";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const backendResponse = await backendRequest("/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    const payload = await parseJsonSafe(backendResponse);
    return Response.json(payload, { status: backendResponse.status });
  } catch {
    return Response.json(
      { error: "Unable to reach backend authentication service." },
      { status: 502 },
    );
  }
}
