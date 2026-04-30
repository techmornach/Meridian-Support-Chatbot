function backendBaseUrl(): string {
  return process.env.BACKEND_API_URL || "";
}

function toAbsoluteBackendPath(path: string): string {
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  return `${backendBaseUrl()}${cleanPath}`;
}

export async function backendRequest(
  path: string,
  init: RequestInit,
): Promise<Response> {
  return fetch(toAbsoluteBackendPath(path), {
    ...init,
    cache: "no-store",
  });
}

export async function parseJsonSafe(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    return null;
  }
  return response.json();
}
