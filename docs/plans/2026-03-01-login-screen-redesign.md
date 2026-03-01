# Login Screen Redesign

## Problem

The current login screen is QR-code-dominant. The nsec input feels like a second-class citizen, and the Primal signer button is squeezed awkwardly between the QR and input.

## Design

### Layout: Stacked cards with single input field

```
┌─────────────────────────────┐
│         [X]                 │
│                             │
│        Olas Logo            │
│    "Welcome to Olas"        │
│                             │
│  ┌───────────────────────┐  │
│  │  Login with Primal    │  │  ← Hero button, only when detected
│  └───────────────────────┘  │
│                             │
│  ── or ──────────────────── │  ← Divider (only when Primal shown)
│                             │
│  ┌───────────────────────┐  │
│  │ nsec or bunker://     │  │
│  │ ┌───────────────┐ 📋  │  │
│  │ │               │     │  │
│  │ └───────────────┘     │  │
│  │ [      Connect      ] │  │  ← Shows when text entered
│  └───────────────────────┘  │
│                             │
│     [Show QR Code]          │  ← Tertiary/link style button
│                             │
└─────────────────────────────┘
```

### Key Decisions

1. **QR code hidden by default** - revealed inline via "Show QR Code" toggle button
2. **Primal hero button** when detected - prominent, accent-colored, full-width, with Primal logo
3. **Single input field** accepts both nsec and bunker:// (no split)
4. **"or" divider** only shown when Primal button is visible
5. **QR reveals inline** (not modal/sheet) - slides in below input area, ~200pt square

### State Variants

- **No signer detected**: Primal button and divider hidden. Input field is primary focus.
- **Primal detected**: Hero button at top, divider, then input field.
- **Reconnect mode**: Reconnect banner at top. No Primal button. Input placeholder shows "bunker://". QR available.
- **QR expanded**: QR code visible below input, "Show QR Code" becomes "Hide QR Code", "Waiting for connection..." spinner shown.
