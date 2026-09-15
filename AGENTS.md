# Open Ratio

Build a native macOS app using SwiftUI and AppKit. Keep the accounting domain independent of operating-system adapters and views. No webview, network service, analytics, or third-party dependencies are needed.

The user's later design correction is authoritative: faithfully reproduce the compact menu bar panel in `docs/reference-panel.png`, not a large dashboard. All data and preferences remain local. See ticket06 and the refinement at the top of the spec.

## Agent skills

### Issue tracker

Use the local Markdown tracker described in `docs/agents/issue-tracker.md`.

### Domain docs

Read `CONTEXT.md` and relevant `docs/adr/` before changing behavior. Single context; see `docs/agents/domain.md`.

## Working agreements

- Use the user-invoked implement skill, with TDD at the public accounting and persistence seams documented in the spec. Test behavior and concrete worked examples.
- The user delegated clarification to an internal two-agent grill. Its settled seams, scope and ticket granularity are recorded in `docs/design-review.md`; do not reopen routine approvals.
- Use system frameworks only. Compile regularly with `swift build`; run focused tests while implementing and `swift test` at integrated completion.
- Changes must preserve real activity across demo entry, reset and exit. Never manufacture tracked real data.
- Keep website capture optional and host only, with one toggle for the system default browser. Other browsers and permission failures must use app-level tracking.
- Commit only owned changes to the current branch. The coordinator runs the final two-axis code review against the planning baseline after implementation tickets land.
- Claim a ticket by changing Status to in-progress; mark completed only with acceptance evidence. The parent spec stays unchanged.
- Keep `.scratch/` planning files and ignored documentation local and untracked; never force-add them to Git.

## Coding standards

Use meaningful domain names and small interfaces. Views render state and invoke actions; accounting, persistence and host normalization live outside views. Handle file errors visibly and retain unreadable originals. Avoid force-unwraps except fixed resources with an explained invariant. Time calculations must accept deterministic inputs for tests.
