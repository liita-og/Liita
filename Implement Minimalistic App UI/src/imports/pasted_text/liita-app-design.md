Design a complete dark-mode mobile app UI called "Liita" — a premium social discovery app for airline passengers. Think Linear meets Locket — brutally minimal, but alive. No emojis anywhere. No lorem ipsum — use realistic data throughout.

━━━━━━━━━━━━━━━━━━━━━━━━
DESIGN SYSTEM
━━━━━━━━━━━━━━━━━━━━━━━━

Colors (strict — use nothing outside this palette):
  Background:    #0B0F19
  Surface:       #161B26
  Surface raised: #1E2333
  Border:        rgba(255,255,255,0.07)
  Accent:        #6366F1  (indigo — one accent colour, used sparingly)
  Cyan glow:     #00F2FE  (only for mesh/connection status indicators)
  Success:       #10B981  (only for "connected" states)
  Text primary:  #F3F4F6
  Text secondary: #9CA3AF
  Text muted:    #4B5563

Typography: Inter throughout
  Headings: weight 700, tight letter-spacing (-0.02em)
  Body: weight 400, line-height 1.5
  Labels/badges: weight 600, uppercase, 0.06em tracking, 11px

Surfaces: Glassmorphism — backdrop-blur-md, background rgba(22,27,38,0.8), border rgba(255,255,255,0.07), border-radius 16px
Shadows: Soft, dark — never white glow. Accent glow only on primary CTAs.
Spacing: 8pt grid. Generous padding (20–24px on screens). Tight internal component spacing (8–12px).
Radius: Cards 16px. Buttons 12px. Badges/pills 999px. Avatars circle.
Animations: Note them in comments — 260ms ease-out-cubic for reveals, spring physics for cards.

Avatars: Initials-based. Coloured backgrounds from a fixed set: #6366F1, #8B5CF6, #EC4899, #F59E0B, #10B981, #3B82F6. White initials, weight 600.

Bottom tab bar (present on all main screens, NOT onboarding):
  Tabs: Radar · Lounge · Games · Matches · Profile
  Style: Glassmorphic floating bar, 12px from bottom, 32px side margins, 20px tall icons, active tab has indigo dot indicator below icon, NO labels.

Design for 390×844 iPhone canvas.

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 1 — RADAR
━━━━━━━━━━━━━━━━━━━━━━━━

The main discovery screen. Layout: dark background, stacked card deck in the vertical centre.

Header (top, minimal):
  Left: "Radar" in 22px/700 weight
  Right: A small pill — cyan dot (pulsing) + "14 nearby" in 12px/600. The dot is the only cyan element on screen.

Card Stack (the hero — takes up ~65% of screen height):
  Show 4 cards in a perspective stack. Cards recede into the background — each one behind is scaled down by 4% and drops in opacity by 15%. Only the front card is fully interactive.

  Front card (full detail):
    - Full-width glassmorphic card, 16px radius
    - Top section: Avatar (64px circle, initials) left-aligned, name in 20px/700 right of avatar, seat badge (e.g. "14C") as a small indigo pill next to name, occupation in 13px secondary colour below name
    - Middle: Thin separator, then the icebreaker prompt label in 11px muted uppercase tracking ("ICEBREAKER"), followed by the answer in 15px primary text, italic, 2 lines max
    - Bottom: Two buttons side by side — "Wave" (indigo filled, 12px radius, slight glow) and "Message" (surface filled, border only)

  Cards 2, 3, 4 behind: Only show the top ~20px of each card peeking out beneath the one above. Each has reduced scale + opacity (use transform: scale and opacity). Card 2 shows a blurred hint of name and avatar. Cards 3 and 4 are just shapes.

Below the stack:
  Small pagination-style indicator — 4 dots, active dot is indigo and wider (pill shape). Centered.

Mock data for cards:
  Card 1: Priya Mehta · 14C · UX Designer · "I'll talk to anyone if they bring good energy"
  Card 2: James Okafor · 7B · Photographer · "I once hitchhiked across three countries"
  Card 3: Sofia Lin · 22A · Architect · "Coffee and deadlines, that's the whole personality"
  Card 4: Arjun Nair · 31D · Startup Founder · "Failed twice. Third time's the flight."

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 2 — LOUNGE
━━━━━━━━━━━━━━━━━━━━━━━━

Full-screen broadcast chat. The flight-wide public room.

Header:
  "Flight Lounge" in 18px/700
  Below it: "47 passengers · EK512 · Dubai → Mumbai" in 13px muted
  Right of header: a faint signal icon

Chat feed (scrollable, takes remaining height above input):
  Messages are left-aligned rows. Each has:
    - Small avatar (32px) on far left
    - Above bubble: sender name (12px/600) + seat badge pill ("22A") inline, space between
    - Message bubble: Surface raised colour, 12px radius, no tail, 14px text, max 75% width
    - Timestamp: 10px muted, right-aligned below bubble
  
  Show 5 messages in sequence:
    Sofia Lin [22A]: "Does anyone know if there's wifi on this flight?"
    James Okafor [7B]: "There is but it's painfully slow. Download stuff before boarding next time."
    Priya Mehta [14C]: "I've been watching downloaded stuff the whole time, no regrets"
    You [20A]: "This app is wild. Didn't know this existed until 5 mins ago" — this one is right-aligned, indigo bubble tint, marked as "You"
    Arjun Nair [31D]: "Same. Building something similar actually, let's talk"

Input bar (pinned to bottom, above tab bar):
  Glassmorphic background, 12px radius, full width minus 20px side margins
  Text field: placeholder "Message the flight..." in muted, 14px
  Send button: small indigo circle with arrow icon, appears only when text is present (show active state)

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 3 — GAMES
━━━━━━━━━━━━━━━━━━━━━━━━

Header: "Games" 22px/700

Hero section (top, centred):
  Large circle (80px) with a dark surface background and indigo controller icon (24px), soft indigo glow behind circle
  Below: "Coming Soon" in 18px/700
  Below: "Play with passengers on your flight" in 14px secondary, centred

Three game cards (vertical list, 12px gap):
  Each card: glassmorphic row, 16px radius, 16px internal padding
  Layout: coloured icon circle (40px) on left · title 15px/600 + description 13px muted on right · "Soon" pill badge (surface raised, muted text) far right

  Game 1: Tic-Tac-Toe · "Classic, now at 30,000 feet" · Icon: grid — colour #6366F1
  Game 2: Trivia · "Test your knowledge against the cabin" · Icon: question mark — colour #00F2FE
  Game 3: Word Chain · "Keep the chain going or lose" · Icon: link — colour #10B981

Cards should look tappable but have a subtle locked overlay (5% white overlay + "Soon" pill). Make them feel like something to look forward to.

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 4 — MATCHES
━━━━━━━━━━━━━━━━━━━━━━━━

Header: "Matches" 22px/700, subtitle "Mutual waves" in 13px muted below

Match list (scrollable):
  Each match row: glassmorphic card, 16px radius
  Layout:
    - Two overlapping avatars (44px each, second overlaps first by 12px)
    - Right of avatars: names joined with "×" in muted (e.g. "You × Priya Mehta"), below that: their seats "14C" as a small badge
    - Far right: "Message" button — small, surface filled with border, 10px radius, 13px/600 text

  Show 2 matches:
    Match 1: You × Priya Mehta · 14C · Matched 4 min ago
    Match 2: You × James Okafor · 7B · Matched 11 min ago

Below the matches, an empty-state hint in small muted text:
  "Wave at someone on the Radar to get a match"

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 5 — PROFILE
━━━━━━━━━━━━━━━━━━━━━━━━

No app bar. Content starts below safe area.

Top section (centred):
  Avatar circle 80px, initials "PM" on indigo bg
  Name: "Pradyumna" 22px/700 below
  Seat badge "20A" + occupation "Software Engineer" on same line below name, separated by a dot in muted

Stats row (3 equal columns, glassmorphic container):
  Waves Sent: 6
  Matches: 2
  Messages: 14
  Each column: number in 22px/700 accent, label in 11px muted uppercase below

Icebreaker card (glassmorphic):
  Label "ICEBREAKER" in 11px muted uppercase tracking
  Prompt in 13px muted italic: "What's something most people don't know about you?"
  Answer in 15px primary: "I learned to code on a Nokia phone when I was 13"

Flight info card (glassmorphic):
  "EK512 · Dubai → Mumbai" in 14px/600
  Below: "Seat 20A · Economy" in 13px muted

Bottom: "End Flight Session" button — full-width, 12px radius, surface raised background, border in red/10%, text in red #EF4444. Should look like a danger action but not alarming — subtle.

━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN 6 — ONBOARDING (Step 3 of 6)
━━━━━━━━━━━━━━━━━━━━━━━━

Clean, focused. No tab bar.

Top: Progress bar — 6 segments, 3 filled in indigo, 3 in surface raised. 4px height, full width, 8px from top.

Back arrow (top left, 40px tap target, muted chevron icon)

Content (vertically centred in remaining space):
  Step label: "Step 3 of 6" in 12px muted
  Title: "Where are you sitting?" in 28px/700, tight tracking
  Subtitle: "We use this to position you relative to nearby passengers" in 14px secondary

  Seat input: Large centred input, 64px height, 16px radius, glassmorphic. Text centred, 32px/700, placeholder "20A" in muted. Keyboard type: text, all caps. Indigo border on focus.

  Cabin class picker (pill group, centred):
    Three pills: Economy · Business · First
    Selected (Economy): indigo background, white text
    Unselected: surface raised, muted text
    8px gap between pills

Large gap, then:
  "Continue" button — full-width, 52px height, 12px radius, indigo solid fill (#6366F1), white text 16px/600. Subtle indigo glow shadow beneath (box-shadow: 0 8px 24px rgba(99,102,241,0.35)).

Bottom safe area padding.

━━━━━━━━━━━━━━━━━━━━━━━━
FINAL INSTRUCTIONS
━━━━━━━━━━━━━━━━━━━━━━━━

- Render all 6 screens side by side or stacked
- Every screen must feel like it belongs to the same design system — same spacing, same card style, same typography scale
- NO emojis anywhere
- NO decorative illustrations — depth and quality come from surfaces, shadows, and type
- The overall feel: calm, focused, premium. Like Linear or Arc but for a social flight app. Not playful, not corporate — human and refined.
- Add realistic interaction states where obvious (focus rings, button hover/press states, active tab)