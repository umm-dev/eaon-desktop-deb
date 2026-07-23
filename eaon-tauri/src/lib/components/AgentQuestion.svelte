<script lang="ts">
  // The Agent's ask_user dialog — mirrors the macOS AgentQuestionDialog:
  // the model's question, one button per offered option, and a free-text
  // field so the user can always answer in their own words instead.
  import { app } from "$lib/state.svelte";
  import * as api from "$lib/api";
  import { onMount } from "svelte";
  import Icon from "./Icon.svelte";

  let custom = $state("");
  let customInput = $state<HTMLInputElement | null>(null);
  let capturedEnterAnswer: string | null = null;

  function answer(text: string) {
    const trimmed = text.trim();
    if (!trimmed) return;
    void api.traceUiEvent(`agent-question answer length=${trimmed.length}`);
    custom = "";
    app.answerAgentQuestion(trimmed);
  }

  onMount(() => {
    const isEnter = (event: KeyboardEvent) =>
      event.key === "Enter" || event.key === "Return"
      || event.code === "Enter" || event.code === "NumpadEnter" || event.keyCode === 13;

    const captureKeydown = (event: KeyboardEvent) => {
      if (!isEnter(event) || !app.pendingAgentQuestion || !custom.trim()) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!event.repeat) capturedEnterAnswer = custom;
    };

    const captureKeyup = (event: KeyboardEvent) => {
      const enter = event.key === "Enter" || event.key === "Return"
        || event.code === "Enter" || event.code === "NumpadEnter" || event.keyCode === 13;
      if (!enter || !app.pendingAgentQuestion || !capturedEnterAnswer) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      const captured = capturedEnterAnswer;
      capturedEnterAnswer = null;
      // Match the working button path: move focus away from the text editor,
      // let WebKitGTK finish its native IME/key handling, then remove the
      // modal and continue the Agent request.
      customInput?.blur();
      setTimeout(() => answer(captured), 250);
    };
    window.addEventListener("keydown", captureKeydown, true);
    window.addEventListener("keyup", captureKeyup, true);
    return () => {
      window.removeEventListener("keydown", captureKeydown, true);
      window.removeEventListener("keyup", captureKeyup, true);
    };
  });
</script>

{#if app.pendingAgentQuestion}
  {@const pending = app.pendingAgentQuestion}
  <div class="overlay">
    <div class="card">
      <div class="title">
        <span class="mark"><Icon name="info" size={16} /></span>
        Eaon has a question
      </div>
      <p class="question">{pending.question}</p>
      {#if pending.options.length}
        <div class="options">
          {#each pending.options as option (option)}
            <button class="option" onclick={() => answer(option)}>{option}</button>
          {/each}
        </div>
      {/if}
      <div class="custom">
        <input
          bind:this={customInput}
          bind:value={custom}
          placeholder="Or type your own answer…"
        />
        <button
          class="send"
          type="button"
          disabled={!custom.trim()}
          onclick={() => answer(custom)}
        >Answer</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: var(--bg-overlay);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 120;
  }
  .card {
    width: 460px;
    max-width: calc(100vw - 48px);
    background: var(--bg-popover);
    border: 1px solid var(--border-subtle);
    border-radius: 20px;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.3);
    padding: 24px;
    animation: pop 0.18s ease-out;
  }
  @keyframes pop {
    from { transform: scale(0.94); opacity: 0; }
    to { transform: scale(1); opacity: 1; }
  }
  .title {
    display: flex;
    align-items: center;
    gap: 10px;
    font-family: var(--font-mono);
    font-size: 18px;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: 14px;
  }
  .mark { color: var(--accent-user); display: inline-flex; }
  .question {
    font-family: var(--font-sans);
    font-size: 15px;
    color: var(--text-primary);
    line-height: 1.5;
    margin: 0 0 16px;
  }
  .options {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-bottom: 16px;
  }
  .option {
    text-align: left;
    font-family: var(--font-sans);
    font-size: 14px;
    color: var(--text-primary);
    background: var(--bg-input-secondary);
    border: 1px solid var(--border-subtle);
    border-radius: 10px;
    padding: 10px 14px;
    cursor: pointer;
  }
  .option:hover { border-color: var(--border-medium); background: var(--bg-hover); }
  .custom {
    display: flex;
    gap: 8px;
  }
  .custom input {
    flex: 1;
    font-family: var(--font-sans);
    font-size: 13.5px;
    color: var(--text-primary);
    background: var(--bg-input);
    border: 1px solid var(--border-subtle);
    border-radius: 10px;
    padding: 9px 12px;
    outline: none;
  }
  .custom input:focus { border-color: var(--border-medium); }
  .send {
    font-family: var(--font-mono);
    font-size: 13px;
    font-weight: 600;
    padding: 8px 16px;
    border-radius: 10px;
    border: 1px solid transparent;
    background: var(--accent);
    color: var(--accent-fg, #fff);
    cursor: pointer;
  }
  .send:disabled { opacity: 0.5; cursor: default; }
</style>
