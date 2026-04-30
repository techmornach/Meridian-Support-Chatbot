"use client";

import {
  FormEvent,
  KeyboardEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { useRouter } from "next/navigation";
import { clientApiPath } from "@/lib/client-api";

type ConversationMessage = {
  role: string;
  content: string;
  created_at?: string;
};

type ChatReply = {
  reply: string;
};

type StreamDelta = {
  delta?: string;
};

type StreamError = {
  error?: string;
};

const GUARDRAIL_BLOCK_MESSAGE = "Request blocked by input safety guardrail.";
const FRIENDLY_GUARDRAIL_MESSAGE = "Sorry, I can't handle that question.";
const EXPIRED_SESSION_MESSAGE = "Session expired. Please sign in again.";

function toFriendlyChatError(message: string): string {
  return message === GUARDRAIL_BLOCK_MESSAGE
    ? FRIENDLY_GUARDRAIL_MESSAGE
    : message;
}

function TypingDots() {
  return (
    <span className="inline-flex items-center gap-1.5 py-1" aria-label="Assistant is typing">
      <span
        className="h-2 w-2 animate-bounce rounded-full bg-current"
        style={{ animationDelay: "0ms" }}
      />
      <span
        className="h-2 w-2 animate-bounce rounded-full bg-current"
        style={{ animationDelay: "120ms" }}
      />
      <span
        className="h-2 w-2 animate-bounce rounded-full bg-current"
        style={{ animationDelay: "240ms" }}
      />
    </span>
  );
}

function formatTime(value?: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function appendAssistantDelta(
  previous: ConversationMessage[],
  delta: string,
): ConversationMessage[] {
  if (!delta) {
    return previous;
  }

  const next = [...previous];
  for (let index = next.length - 1; index >= 0; index -= 1) {
    if (next[index].role === "assistant") {
      next[index] = {
        ...next[index],
        content: `${next[index].content}${delta}`,
      };
      return next;
    }
  }

  return [...next, { role: "assistant", content: delta }];
}

async function readSseStream(
  response: Response,
  onDelta: (delta: string) => void,
): Promise<void> {
  if (!response.body) {
    throw new Error("Chat stream ended before any response body was returned.");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let done = false;

  while (!done) {
    const result = await reader.read();
    done = result.done;
    buffer += decoder.decode(result.value ?? new Uint8Array(), { stream: !done });

    const frames = buffer.split("\n\n");
    buffer = frames.pop() ?? "";

    for (const frame of frames) {
      const trimmed = frame.trim();
      if (!trimmed) {
        continue;
      }

      const lines = trimmed.split("\n");
      let eventName = "message";
      const dataLines: string[] = [];
      for (const line of lines) {
        if (line.startsWith("event:")) {
          eventName = line.slice("event:".length).trim();
          continue;
        }
        if (line.startsWith("data:")) {
          dataLines.push(line.slice("data:".length).trim());
        }
      }

      const data = dataLines.join("\n");
      if (!data) {
        continue;
      }

      if (eventName === "done" || data === "[DONE]") {
        return;
      }

      if (eventName === "error") {
        const parsed = JSON.parse(data) as StreamError;
        throw new Error(toFriendlyChatError(parsed.error || "Chat stream failed."));
      }

      const parsed = JSON.parse(data) as StreamDelta;
      if (parsed.delta) {
        onDelta(parsed.delta);
      }
    }
  }
}

export default function ChatPage() {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement | null>(null);
  const tokenRef = useRef<string | null>(null);
  const [messages, setMessages] = useState<ConversationMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isLoadingHistory, setIsLoadingHistory] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const handleSessionExpired = useCallback(() => {
    window.alert(EXPIRED_SESSION_MESSAGE);
    window.localStorage.removeItem("auth_token");
    router.replace("/");
  }, [router]);

  useEffect(() => {
    const stored = window.localStorage.getItem("auth_token");
    if (!stored) {
      router.replace("/");
      return;
    }
    tokenRef.current = stored;

    let isMounted = true;
    async function loadConversationHistory() {
      setIsLoadingHistory(true);
      setError(null);
      try {
        const response = await fetch(clientApiPath("/conversations/me"), {
          headers: {
            Authorization: `Bearer ${stored}`,
          },
          cache: "no-store",
        });

        if (response.status === 401) {
          handleSessionExpired();
          return;
        }

        const payload = (await response.json()) as
          | { messages: ConversationMessage[] }
          | { detail?: string; error?: string };

        if (!response.ok || !("messages" in payload)) {
          const message =
            ("detail" in payload && payload.detail) ||
            ("error" in payload && payload.error) ||
            "Failed to fetch conversation history.";
          throw new Error(message);
        }

        if (isMounted) {
          setMessages(payload.messages);
        }
      } catch (historyError) {
        if (isMounted) {
          const message =
            historyError instanceof Error
              ? historyError.message
              : "Unexpected history error.";
          setError(message);
        }
      } finally {
        if (isMounted) {
          setIsLoadingHistory(false);
        }
      }
    }

    void loadConversationHistory();
    return () => {
      isMounted = false;
    };
  }, [handleSessionExpired, router]);

  const canSend = useMemo(
    () => draft.trim().length > 0 && !isSending,
    [draft, isSending],
  );

  async function handleSend(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const token = tokenRef.current;
    if (!token || !draft.trim() || isSending) {
      return;
    }

    const message = draft.trim();
    setDraft("");
    setError(null);
    setIsSending(true);
    setMessages((previous) => [
      ...previous,
      { role: "user", content: message },
      { role: "assistant", content: "" },
    ]);

    try {
      const response = await fetch(clientApiPath("/chat?stream=false"), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ message }),
      });

      if (response.status === 401) {
        handleSessionExpired();
        return;
      }

      if (!response.ok) {
        const payload = (await response.json()) as
          | ChatReply
          | { detail?: string; error?: string };
        const messageText =
          ("detail" in payload && payload.detail) ||
          ("error" in payload && payload.error) ||
          "Failed to get assistant response.";
        throw new Error(toFriendlyChatError(messageText));
      }

      const contentType = response.headers.get("content-type") ?? "";
      if (contentType.includes("text/event-stream")) {
        await readSseStream(response, (delta) => {
          setMessages((previous) => appendAssistantDelta(previous, delta));
        });
      } else {
        const payload = (await response.json()) as
          | ChatReply
          | { detail?: string; error?: string };
        if (!("reply" in payload)) {
          const messageText =
            ("detail" in payload && payload.detail) ||
            ("error" in payload && payload.error) ||
            "Failed to get assistant response.";
          throw new Error(toFriendlyChatError(messageText));
        }
        setMessages((previous) => appendAssistantDelta(previous, payload.reply));
      }
    } catch (chatError) {
      const messageText =
        chatError instanceof Error
          ? chatError.message
          : "Unexpected chat error.";
      setError(messageText);
    } finally {
      setIsSending(false);
    }
  }

  function handleLogout() {
    window.localStorage.removeItem("auth_token");
    router.replace("/");
  }

  function handleDraftKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      formRef.current?.requestSubmit();
    }
  }

  return (
    <main className="min-h-screen px-4 py-6 sm:px-8">
      <section className="mx-auto flex h-[calc(100vh-3rem)] w-full max-w-5xl flex-col rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)]">
        <header className="flex items-center justify-between border-b border-[var(--color-border)] px-5 py-4">
          <div>
            <p className="text-xs uppercase tracking-[0.24em] text-[var(--color-fg-muted)]">
              Meridian Support
            </p>
            <h1 className="mt-1 text-lg font-semibold">Chat</h1>
          </div>
          <button
            type="button"
            onClick={handleLogout}
            className="rounded-md border border-[var(--color-border)] bg-[var(--color-surface-alt)] px-3 py-2 text-sm transition hover:border-white"
          >
            Log out
          </button>
        </header>

        <div className="flex-1 space-y-4 overflow-y-auto px-4 py-4 sm:px-6">
          {isLoadingHistory ? (
            <p className="text-sm text-[var(--color-fg-muted)]">
              Loading conversation history...
            </p>
          ) : null}

          {!isLoadingHistory && messages.length === 0 ? (
            <p className="text-sm text-[var(--color-fg-muted)]">
              Start a conversation with support.
            </p>
          ) : null}

          {messages.map((message, index) => {
            const isUser = message.role === "user";
            const isTypingIndicator =
              !isUser && isSending && message.content.trim().length === 0;
            return (
              <article
                key={`${message.role}-${index}-${message.created_at ?? ""}`}
                className={`max-w-[85%] rounded-xl border px-4 py-3 ${
                  isUser
                    ? "ml-auto border-white bg-white text-black"
                    : "border-[var(--color-border)] bg-[var(--color-surface-alt)] text-white"
                }`}
              >
                {isUser ? (
                  <p className="whitespace-pre-wrap text-sm leading-relaxed">
                    {message.content}
                  </p>
                ) : isTypingIndicator ? (
                  <TypingDots />
                ) : (
                  <div className="text-sm leading-relaxed [&_code]:rounded [&_code]:bg-black/20 [&_code]:px-1 [&_code]:py-0.5 [&_ol]:list-decimal [&_ol]:pl-5 [&_p]:my-2 [&_pre]:overflow-x-auto [&_pre]:rounded [&_pre]:bg-black/30 [&_pre]:p-3 [&_ul]:list-disc [&_ul]:pl-5">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>
                      {message.content}
                    </ReactMarkdown>
                  </div>
                )}
                <p
                  className={`mt-2 text-[11px] ${
                    isUser ? "text-black/70" : "text-[var(--color-fg-muted)]"
                  }`}
                >
                  {isUser ? "You" : "Assistant"}
                  {message.created_at
                    ? ` • ${formatTime(message.created_at)}`
                    : ""}
                </p>
              </article>
            );
          })}
        </div>

        <footer className="border-t border-(--color-border) p-4 sm:p-5">
          {error ? (
            <p className="mb-3 rounded-md border border-[#5a1f1f] bg-[#2a1414] px-3 py-2 text-sm text-[#ffb4b4]">
              {error}
            </p>
          ) : null}

          <form ref={formRef} onSubmit={handleSend} className="flex items-end gap-3">
            <label className="sr-only" htmlFor="chat-message">
              Message
            </label>
            <textarea
              id="chat-message"
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={handleDraftKeyDown}
              placeholder="Ask about your orders, products, or account..."
              rows={2}
              maxLength={4000}
              className="min-h-16 flex-1 resize-y rounded-xl border border-[var(--color-border)] bg-[var(--color-surface-alt)] px-4 py-3 text-sm leading-relaxed outline-none transition focus:border-white"
            />
            <button
              type="submit"
              disabled={!canSend}
              className="rounded-xl border border-white bg-white px-5 py-3 text-sm font-medium text-black transition hover:bg-transparent hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
              {isSending ? "Sending..." : "Send"}
            </button>
          </form>
        </footer>
      </section>
    </main>
  );
}
