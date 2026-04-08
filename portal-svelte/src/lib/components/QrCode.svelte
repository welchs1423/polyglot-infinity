<script lang="ts">
    import { onMount } from "svelte";
    import QRCode from "qrcode";

    // Canvas element bound via bind:this.
    let canvas: HTMLCanvasElement;

    // Current dashboard URL populated on mount (SSR-safe: window unavailable server-side).
    let url = $state("");

    // Controls popover visibility.
    let visible = $state(false);

    onMount(() => {
        url = window.location.href;
    });

    // Toggles the QR popover. Renders the QR code on first open and on URL change.
    async function toggle() {
        visible = !visible;
        if (visible && canvas && url) {
            await QRCode.toCanvas(canvas, url, {
                width: 192,
                margin: 2,
                // Dark/light colours inverted to match the dark dashboard theme.
                color: { dark: "#f1f5f9", light: "#0f172a" },
            });
        }
    }

    // Re-renders the QR code whenever the URL changes while the popover is open.
    $effect(() => {
        if (visible && canvas && url) {
            QRCode.toCanvas(canvas, url, {
                width: 192,
                margin: 2,
                color: { dark: "#f1f5f9", light: "#0f172a" },
            });
        }
    });
</script>

<div class="qr-wrap">
    <button
        class="qr-btn"
        onclick={toggle}
        aria-expanded={visible}
        aria-label="Toggle QR code"
    >
        <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="qr-icon"
            aria-hidden="true"
        >
            <!-- QR corner squares -->
            <rect x="3" y="3" width="7" height="7" rx="1" />
            <rect x="14" y="3" width="7" height="7" rx="1" />
            <rect x="3" y="14" width="7" height="7" rx="1" />
            <!-- Inner dots -->
            <rect x="5" y="5" width="3" height="3" />
            <rect x="16" y="5" width="3" height="3" />
            <rect x="5" y="16" width="3" height="3" />
            <!-- Bottom-right data cells -->
            <path d="M14 14h3v3h-3z" />
            <path d="M18 14h3" />
            <path d="M14 18h3" />
            <path d="M18 18h3v3h-3z" />
        </svg>
        <span>Share</span>
    </button>

    {#if visible}
        <!-- Popover positioned relative to the button container. -->
        <div
            class="qr-popover"
            role="dialog"
            aria-label="QR code for current URL"
        >
            <canvas bind:this={canvas}></canvas>
            <p class="qr-url">{url}</p>
        </div>
    {/if}
</div>

<style>
    .qr-wrap {
        position: relative;
        display: inline-flex;
        align-items: center;
    }

    .qr-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.4rem;
        padding: 0.45rem 0.9rem;
        background: #1e293b;
        border: 1px solid #334155;
        border-radius: 6px;
        color: #94a3b8;
        font-size: 0.82rem;
        font-weight: 600;
        cursor: pointer;
        transition:
            background 0.15s,
            color 0.15s,
            border-color 0.15s;
        white-space: nowrap;
    }

    .qr-btn:hover {
        background: #334155;
        color: #f1f5f9;
        border-color: #475569;
    }

    .qr-icon {
        width: 14px;
        height: 14px;
        flex-shrink: 0;
    }

    .qr-popover {
        position: absolute;
        top: calc(100% + 8px);
        right: 0;
        z-index: 50;
        padding: 0.75rem;
        background: #0f172a;
        border: 1px solid #334155;
        border-radius: 10px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
    }

    .qr-popover canvas {
        display: block;
        border-radius: 6px;
    }

    .qr-url {
        margin: 0;
        max-width: 192px;
        font-size: 0.65rem;
        color: #64748b;
        word-break: break-all;
        text-align: center;
        line-height: 1.4;
    }
</style>
