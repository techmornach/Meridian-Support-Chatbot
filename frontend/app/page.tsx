"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { clientApiPath } from "@/lib/client-api";

type LoginResponse = {
  access_token: string;
  token_type: string;
};

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      const response = await fetch(clientApiPath("/auth/login"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, pin }),
      });
      const payload = (await response.json()) as
        | LoginResponse
        | { detail?: string; error?: string };

      if (!response.ok || !("access_token" in payload)) {
        const message =
          ("detail" in payload && payload.detail) ||
          ("error" in payload && payload.error) ||
          "Login failed. Please check your credentials.";
        throw new Error(message);
      }

      window.localStorage.setItem("auth_token", payload.access_token);
      router.push("/chat");
    } catch (submitError) {
      const message =
        submitError instanceof Error
          ? submitError.message
          : "Unexpected login error.";
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="min-h-screen grid place-items-center px-6 py-12">
      <section className="w-full max-w-md rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-8 shadow-[0_0_0_1px_rgba(255,255,255,0.03)]">
        <div className="mb-8">
          <p className="text-xs uppercase tracking-[0.25em] text-[var(--color-fg-muted)]">
            Meridian Support
          </p>
          <h1 className="mt-3 text-2xl font-semibold">Sign in</h1>
          <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
            Use your customer email and PIN to continue.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="block">
            <span className="mb-2 block text-sm text-[var(--color-fg-muted)]">
              Email
            </span>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              autoComplete="email"
              placeholder="you@example.com"
              className="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-surface-alt)] px-4 py-3 text-sm outline-none transition focus:border-white"
            />
          </label>

          <label className="block">
            <span className="mb-2 block text-sm text-[var(--color-fg-muted)]">
              PIN
            </span>
            <input
              type="password"
              value={pin}
              onChange={(event) =>
                setPin(event.target.value.replace(/\D/g, "").slice(0, 4))
              }
              inputMode="numeric"
              pattern="\d{4}"
              minLength={4}
              maxLength={4}
              required
              autoComplete="one-time-code"
              placeholder="••••"
              className="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-surface-alt)] px-4 py-3 text-sm tracking-[0.35em] outline-none transition focus:border-white"
            />
          </label>

          {error ? (
            <p className="rounded-md border border-[#5a1f1f] bg-[#2a1414] px-3 py-2 text-sm text-[#ffb4b4]">
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={isSubmitting}
            className="mt-2 w-full rounded-lg border border-white bg-white px-4 py-3 text-sm font-medium text-black transition hover:bg-transparent hover:text-white disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isSubmitting ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </section>
    </main>
  );
}
