function normalizedPublicBackendBaseUrl(): string {
  const rawBaseUrl = process.env.NEXT_PUBLIC_BACKEND_API_URL ?? "";
  return rawBaseUrl.trim().replace(/\/+$/, "");
}

export function clientApiPath(path: string): string {
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  const backendBaseUrl = normalizedPublicBackendBaseUrl();

  if (backendBaseUrl) {
    return `${backendBaseUrl}${cleanPath}`;
  }

  return `/api${cleanPath}`;
}
