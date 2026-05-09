# UI/UX Design Document: CACMS

## Design Principles

- **Speed over beauty** — clinic staff are under pressure; every interaction must be ≤ 2 taps/clicks
- **Status at a glance** — queue state, patient status, and counts must be visible without scrolling
- **Error recovery** — every error state has a clear recovery action, never a dead end
- **Role isolation** — each role sees only what they need; no cognitive overload from irrelevant data
- **Offline resilience** — SSE disconnect is surfaced clearly with auto-reconnect indicator

---

## Design System

### Color Palette

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#1A6B8A` | Primary actions, app bars, active states |
| `primary-light` | `#E8F4F8` | Selected row backgrounds, chips |
| `accent` | `#F4A261` | Call Next button, urgent actions |
| `success` | `#2D9E6B` | Completed status, paid badge |
| `warning` | `#E9C46A` | Scheduled status, pending badge |
| `danger` | `#E63946` | Emergency badge, error states, no-show |
| `neutral-900` | `#1A1A2E` | Primary text |
| `neutral-600` | `#6B7280` | Secondary text, labels |
| `neutral-200` | `#E5E7EB` | Dividers, borders |
| `neutral-50` | `#F9FAFB` | Page backgrounds |
| `surface` | `#FFFFFF` | Cards, modals |

### Typography

| Style | Font | Size | Weight | Usage |
|---|---|---|---|---|
| `heading-1` | Inter | 24sp | 700 | Screen titles |
| `heading-2` | Inter | 18sp | 600 | Section headers, card titles |
| `heading-3` | Inter | 16sp | 600 | List item names |
| `body` | Inter | 14sp | 400 | Body text, descriptions |
| `caption` | Inter | 12sp | 400 | Labels, timestamps |
| `badge` | Inter | 11sp | 700 | Status chips, queue numbers |
| `mono` | JetBrains Mono | 13sp | 500 | Queue numbers, IDs |

### Spacing Scale

`4 / 8 / 12 / 16 / 24 / 32 / 48px` — all padding and margins use this scale.

### Elevation

| Level | Shadow | Usage |
|---|---|---|
| 0 | none | Page background |
| 1 | `0 1px 3px rgba(0,0,0,0.08)` | Cards, list items |
| 2 | `0 4px 12px rgba(0,0,0,0.12)` | Modals, bottom sheets |
| 3 | `0 8px 24px rgba(0,0,0,0.16)` | Dialogs, overlays |

### Status Chips

| Status | Background | Text | Icon |
|---|---|---|---|
| `scheduled` | `#FEF9C3` | `#92400E` | 🕐 |
| `in-progress` | `#DBEAFE` | `#1E40AF` | ▶ |
| `completed` | `#D1FAE5` | `#065F46` | ✓ |
| `cancelled` | `#F3F4F6` | `#6B7280` | ✕ |
| `no-show` | `#FEE2E2` | `#991B1B` | ✗ |
| `emergency` | `#FEE2E2` | `#991B1B` | ⚡ |

### Visit Type Badges

| Type | Color |
|---|---|
| `normal` | `neutral-200` text `neutral-600` |
| `follow-up` | `#EDE9FE` text `#5B21B6` |
| `emergency` | `danger` text white |

---

## Navigation Structure

### Admin App

```
Login Screen
    └── Home (single-screen dashboard)
            ├── Patient Lookup / Quick Register (inline panel)
            ├── Appointment Creation (inline panel)
            ├── Live Queue View (right panel / bottom sheet)
            └── Payment Screen (modal)
```

### Doctor App

```
Login Screen
    └── Queue Dashboard (home)
            ├── Call Next (inline action)
            └── Consultation Form (full screen)
                    └── Follow-Up Prompt (bottom sheet)
```

### Patient App

```
OTP Login Screen
    ├── Phone Entry
    └── OTP Verification
            └── Live Status Screen
                    └── Visit Summary (expanded card)
```

---

## Screen Designs

---

### ADMIN SCREENS

---

#### A1 — Admin Login

```
┌─────────────────────────────────────┐
│                                     │
│         🏥  CACMS                   │
│         Clinic Management           │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Username / Email           │    │
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │  Password              👁   │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │      LOGIN  →               │    │  ← primary button, full width
│  └─────────────────────────────┘    │
│                                     │
│  [Error banner — hidden by default] │
└─────────────────────────────────────┘
```

**States:**
- Default: empty fields
- Loading: button shows spinner, fields disabled
- Error: red banner below button — "Invalid credentials"

---

#### A2 — Admin Home (One-Screen UX)

This is the core admin screen. It is a two-panel layout on tablet/desktop and a stacked layout on phone.

```
┌──────────────────────────────────────────────────────────────────┐
│  🏥 CACMS Admin          Today: Thu 16 Apr        [Logout]       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  LEFT PANEL (60%)                  RIGHT PANEL (40%)            │
│  ┌──────────────────────────────┐  ┌──────────────────────────┐ │
│  │ PATIENT LOOKUP               │  │ LIVE QUEUE               │ │
│  │                              │  │                          │ │
│  │ 📱 Phone Number              │  │ Dr. Sharma  ▼            │ │
│  │ ┌──────────────────────┐     │  │                          │ │
│  │ │ +91 __________  🔍   │     │  │ Total: 12  Done: 4       │ │
│  │ └──────────────────────┘     │  │ Remaining: 8             │ │
│  │                              │  │                          │ │
│  │ ── Patient Found ──────────  │  │ ┌──────────────────────┐ │ │
│  │ ┌──────────────────────────┐ │  │ │ #1  Rahul M.  ✓done  │ │ │
│  │ │ Rahul Mehta              │ │  │ │ #2  Priya S.  ▶ now  │ │ │
│  │ │ Age: 34  Male            │ │  │ │ #3  Amit K.   🕐     │ │ │
│  │ │ Last visit: 10 Mar 2026  │ │  │ │ #4  Sunita R. 🕐     │ │ │
│  │ └──────────────────────────┘ │  │ │ #5  ⚡ EMERGENCY 🕐  │ │ │
│  │                              │  │ └──────────────────────┘ │ │
│  │ ── New Appointment ────────  │  │                          │ │
│  │                              │  │ [SSE ● Live]             │ │
│  │ Doctor:  [Dr. Sharma    ▼]   │  └──────────────────────────┘ │
│  │ Date:    [16 Apr 2026   📅]  │                              │
│  │ Type:    [Normal ▼]          │                              │
│  │                              │                              │
│  │ ┌──────────────────────────┐ │                              │
│  │ │  CREATE APPOINTMENT  →   │ │  ← accent color             │
│  │ └──────────────────────────┘ │                              │
│  └──────────────────────────────┘                              │
└──────────────────────────────────────────────────────────────────┘
```

**Patient Lookup States:**

1. Empty — just the phone input field
2. Searching — spinner inside input
3. Found — patient card slides in below input
4. Not Found — inline registration form expands:

```
│  ── New Patient Registration ──────  │
│  ┌──────────────────────────────┐    │
│  │ Full Name                    │    │
│  └──────────────────────────────┘    │
│  ┌──────────┐  ┌────────────────┐    │
│  │ Age      │  │ Gender    ▼    │    │
│  └──────────┘  └────────────────┘    │
│  ☑ Patient consents to data use      │
│  ┌──────────────────────────────┐    │
│  │  REGISTER & CONTINUE  →      │    │
│  └──────────────────────────────┘    │
```

**Appointment Creation States:**
- Default: doctor/date/type selectors
- Loading: button spinner
- Success: green toast "Queue #7 assigned to Rahul Mehta" — queue panel updates live
- Capacity Error: red inline message "Dr. Sharma has reached today's limit (40 patients)"
- Emergency: visit type = Emergency shows red badge preview

**Live Queue Panel:**
- SSE connection indicator: `● Live` (green dot) or `⚠ Reconnecting...` (amber)
- Queue rows update in real-time without page refresh
- Emergency appointments shown with ⚡ badge, sorted to top

---

#### A3 — Payment Modal

Triggered from queue row → "Record Payment" action.

```
┌─────────────────────────────────────┐
│  Payment — Rahul Mehta              │  ← modal overlay
│  Consultation #C-2041               │
├─────────────────────────────────────┤
│                                     │
│  Services Rendered:                 │
│  • Consultation Fee      ₹ 500      │
│  • EEG                   ₹ 1,200    │
│  ─────────────────────────────────  │
│  Total                   ₹ 1,700    │
│                                     │
│  Payment Mode:                      │
│  ┌────────┐ ┌────────┐ ┌────────┐   │
│  │  Cash  │ │  UPI   │ │  Card  │   │  ← segmented control
│  └────────┘ └────────┘ └────────┘   │
│                                     │
│  Amount:  ┌──────────────────────┐  │
│           │ ₹ 1,700              │  │
│           └──────────────────────┘  │
│                                     │
│  Status:  [Paid ▼]                  │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  RECORD PAYMENT  →          │    │
│  └─────────────────────────────┘    │
│                          [Cancel]   │
└─────────────────────────────────────┘
```

---

### DOCTOR SCREENS

---

#### D1 — Doctor Login

Same layout as A1 with "Doctor Portal" subtitle.

---

#### D2 — Doctor Queue Dashboard

```
┌─────────────────────────────────────────────────────┐
│  Dr. Sharma — Neurology          Thu 16 Apr  [⚙]   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  Total   │  │  Done    │  │ Remaining│          │
│  │   12     │  │    4     │  │    8     │          │
│  └──────────┘  └──────────┘  └──────────┘          │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  ▶  CALL NEXT PATIENT                       │   │  ← large accent button
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  NOW SEEING                                         │
│  ┌─────────────────────────────────────────────┐   │
│  │  #2  Priya Sharma          follow-up        │   │
│  │  Age: 28  F                                 │   │
│  │  ┌─────────────────────────────────────┐   │   │
│  │  │  START CONSULTATION  →              │   │   │
│  │  └─────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  QUEUE                                              │
│  ┌─────────────────────────────────────────────┐   │
│  │  #1  Rahul Mehta        normal    ✓ done    │   │
│  │  #2  Priya Sharma       follow-up ▶ now     │   │
│  │  #3  Amit Kumar         normal    🕐        │   │
│  │  #4  Sunita Rao         normal    🕐        │   │
│  │  #5  ⚡ Vikram Singh    emergency 🕐        │   │
│  │  #6  Meena Patel        normal    🕐        │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  [SSE ● Live]                                       │
└─────────────────────────────────────────────────────┘
```

**Call Next Button States:**
- Default: accent orange, full width, "CALL NEXT PATIENT"
- Loading: spinner, disabled — prevents double-tap
- Success: queue list animates, "Now Seeing" card updates
- Queue Empty: button becomes grey "Queue Complete ✓", empty state illustration
- Conflict: brief toast "Another request in progress, please retry" — button re-enables after 1s

**Queue Row Interactions:**
- Tap row → expand to show: mark no-show, mark cancelled actions
- Emergency rows always pinned to top of scheduled section
- Completed rows shown in muted style at bottom

---

#### D3 — Consultation Form

Full-screen, scrollable.

```
┌─────────────────────────────────────────────────────┐
│  ←  Consultation                                    │
│  Priya Sharma  •  #2  •  follow-up                  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  SYMPTOMS                                           │
│  ┌─────────────────────────────────────────────┐   │
│  │ Describe symptoms...                        │   │  ← multiline, min 3 rows
│  │                                             │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  DIAGNOSIS                                          │
│  ┌─────────────────────────────────────────────┐   │
│  │ Diagnosis...                                │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  NOTES  (optional)                                  │
│  ┌─────────────────────────────────────────────┐   │
│  │ Additional notes...                         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  SERVICES                                           │
│  ┌─────────────────────────────────────────────┐   │
│  │  + Add Service                              │   │
│  │  ─────────────────────────────────────────  │   │
│  │  Consultation Fee    x1   ₹500    [✕]       │   │
│  │  EEG                 x1   ₹1,200  [✕]       │   │
│  │  ─────────────────────────────────────────  │   │
│  │  Total:  ₹ 1,700                            │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  NEXT VISIT DATE  (optional)                        │
│  ┌─────────────────────────────────────────────┐   │
│  │  📅  Select date...                         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  COMPLETE CONSULTATION  →                   │   │  ← primary button
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Add Service Bottom Sheet:**

```
┌─────────────────────────────────────┐
│  Add Service              [✕]       │
├─────────────────────────────────────┤
│  🔍 Search services...              │
│                                     │
│  CONSULTATION                       │
│  • Consultation Fee      ₹ 500  [+] │
│                                     │
│  TESTS                              │
│  • EEG                   ₹ 1,200 [+]│
│  • Blood CBC             ₹ 350   [+]│
│  • MRI Brain             ₹ 4,500 [+]│
│                                     │
│  PROCEDURES                         │
│  • Dressing              ₹ 200   [+]│
└─────────────────────────────────────┘
```

**Follow-Up Prompt Bottom Sheet** (appears after successful consultation save when `next_visit_date` is set):

```
┌─────────────────────────────────────┐
│  📅 Schedule Follow-Up?             │
├─────────────────────────────────────┤
│  Patient:  Priya Sharma             │
│  Doctor:   Dr. Sharma               │
│  Date:     23 Apr 2026              │
│  Type:     Follow-Up                │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  BOOK FOLLOW-UP  →          │    │
│  └─────────────────────────────┘    │
│                    [Skip for now]   │
└─────────────────────────────────────┘
```

---

### PATIENT SCREENS

---

#### P1 — OTP Login: Phone Entry

```
┌─────────────────────────────────────┐
│                                     │
│         🏥  CACMS                   │
│         Patient Portal              │
│                                     │
│  Enter your registered              │
│  mobile number                      │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ +91  │  Phone number        │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  SEND OTP  →                │    │
│  └─────────────────────────────┘    │
│                                     │
│  Your number is used only to        │
│  identify your appointment.         │
└─────────────────────────────────────┘
```

---

#### P2 — OTP Login: OTP Verification

```
┌─────────────────────────────────────┐
│  ←                                  │
│                                     │
│  Enter OTP sent to                  │
│  +91 98765 XXXXX                    │
│                                     │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐        │
│  │    │ │    │ │    │ │    │        │  ← 4/6 digit OTP boxes
│  └────┘ └────┘ └────┘ └────┘        │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  VERIFY  →                  │    │
│  └─────────────────────────────┘    │
│                                     │
│  Resend OTP in 00:45                │
│                                     │
│  [Error: Invalid OTP — try again]   │  ← hidden by default
└─────────────────────────────────────┘
```

---

#### P3 — Patient Live Status Screen

This screen has four distinct states driven by appointment status.

**State 1: No Active Appointment**

```
┌─────────────────────────────────────┐
│  Hi, Priya 👋                       │
│  No appointment today               │
├─────────────────────────────────────┤
│                                     │
│  LAST VISIT                         │
│  ┌─────────────────────────────┐    │
│  │  10 Mar 2026                │    │
│  │  Dr. Sharma — Neurology     │    │
│  │                             │    │
│  │  Diagnosis:                 │    │
│  │  Tension headache           │    │
│  │                             │    │
│  │  Next visit: 23 Apr 2026    │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

**State 2: Scheduled — Waiting**

```
┌─────────────────────────────────────┐
│  Hi, Priya 👋                       │
│  Your appointment today             │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │     YOUR QUEUE NUMBER       │    │
│  │                             │    │
│  │          ┌─────┐            │    │
│  │          │  5  │            │    │  ← large mono number
│  │          └─────┘            │    │
│  │                             │    │
│  │   Dr. Sharma is on #2       │    │
│  │   ~3 patients ahead of you  │    │
│  │                             │    │
│  │   🕐 Estimated wait: 30 min │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  [SSE ● Live updates on]            │
└─────────────────────────────────────┘
```

**State 3: In-Progress — Being Seen**

```
┌─────────────────────────────────────┐
│  Hi, Priya 👋                       │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │   ▶  You are being seen     │    │  ← blue pulsing indicator
│  │      now                    │    │
│  │                             │    │
│  │   Dr. Sharma — Neurology    │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

**State 4: Completed — Visit Summary**

```
┌─────────────────────────────────────┐
│  Hi, Priya 👋                       │
│  Visit complete ✓                   │
├─────────────────────────────────────┤
│                                     │
│  VISIT SUMMARY                      │
│  ┌─────────────────────────────┐    │
│  │  16 Apr 2026                │    │
│  │  Dr. Sharma — Neurology     │    │
│  │                             │    │
│  │  Diagnosis:                 │    │
│  │  Migraine with aura         │    │
│  │                             │    │
│  │  Services:                  │    │
│  │  • Consultation Fee  ₹ 500  │    │
│  │  • EEG              ₹ 1,200 │    │
│  │  Total:             ₹ 1,700 │    │
│  │                             │    │
│  │  Next Visit: 23 Apr 2026    │    │
│  │  Dr. Sharma                 │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

---

## Interaction Flows

### Admin: Create Appointment in ≤ 30 Seconds

```
Enter phone (2s)
    → Search (500ms)
    → Patient found: tap "New Appointment" (1s)
    → Select doctor from dropdown (2s)
    → Date defaults to today (0s)
    → Select visit type (1s)
    → Tap CREATE (1s API call)
    → Queue number shown in toast (0s)
Total: ~8 seconds typical path
```

### Admin: New Patient + Appointment

```
Enter phone (2s)
    → Not found: registration form expands (0s)
    → Enter name, age, gender (10s)
    → Tap REGISTER & CONTINUE (500ms)
    → Appointment form pre-filled (0s)
    → Select doctor + type (3s)
    → Tap CREATE (1s)
Total: ~17 seconds
```

### Doctor: Call Next Flow

```
Tap CALL NEXT (1 tap)
    → Button shows spinner (locks against double-tap)
    → API call completes (500ms)
    → "Now Seeing" card updates
    → Queue list animates (completed row moves to done style)
    → SSE event updates Admin's live queue panel simultaneously
```

### Patient: SSE Reconnect Flow

```
Connection drops
    → Status indicator changes to "⚠ Reconnecting..."
    → Client retries with exponential backoff (1s, 2s, 4s...)
    → On reconnect: sends Last-Event-ID header
    → Server replays missed events
    → Status indicator returns to "● Live"
    → UI state updates to reflect any missed status changes
```

---

## Responsive Breakpoints

| Breakpoint | Layout |
|---|---|
| Phone (< 600px) | Single column, bottom sheets for panels |
| Tablet (600–1024px) | Two-panel side-by-side (Admin home) |
| Desktop (> 1024px) | Two-panel + expanded queue sidebar |

### Admin Home — Phone Layout

On phone, the right panel (Live Queue) becomes a floating action button "View Queue →" that opens a bottom sheet showing the queue list.

---

## Accessibility Notes

- All interactive elements have minimum 44×44px touch targets
- Status chips use both color and icon/text (not color alone)
- Queue numbers use monospace font for quick scanning
- Error messages are placed adjacent to the triggering field
- SSE connection status is always visible (not hidden in a menu)
- OTP input supports autofill from SMS on Android/iOS

---

## Empty States

| Screen | Empty State Message |
|---|---|
| Doctor dashboard — no appointments | "No appointments scheduled for today" + illustration |
| Doctor dashboard — queue complete | "All patients seen today ✓" + success illustration |
| Patient — no appointment | "No appointment today" + last visit summary |
| Services list — no active services | "No services configured. Contact admin." |
| Admin queue panel — no doctor selected | "Select a doctor to view their queue" |

---

## Toast / Notification Patterns

| Event | Toast | Duration |
|---|---|---|
| Appointment created | ✓ "Queue #7 assigned to [Name]" | 3s |
| Call Next success | ✓ "Now seeing [Name] (#2)" | 2s |
| Queue empty | "Queue complete for today" | 3s |
| Call Next conflict | ⚠ "Retry in a moment" | 2s |
| SSE reconnected | ✓ "Live updates restored" | 2s |
| Payment recorded | ✓ "Payment recorded" | 3s |
| Error (generic) | ✕ "[error message]" | 5s, dismissible |
