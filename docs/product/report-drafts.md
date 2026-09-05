> Deferred on 2026-09-05. The user simplified the app to Today, Time Clock, and the Full Scale Report website. This historical proposal is outside the current release.

# Daily report drafts

Status: proposed first release, confirmed 2026-09-05: local drafts and review/copy first. On-device Improve is the recommended optional addition within the draft phase, subject to availability and quality checks. Direct posting follows verified integration work. Field requirements below come from the user's supplied form; the authenticated destination contract remains to be verified.

## Workflow

1. **Capture during work.** Open the global shortcut, add a short work note or edit today's draft, and return to work. Blank or incomplete drafts can always be saved.
2. **Prepare the report.** Open the report window, review work date/project/recipients, and move relevant notes into the report fields. Original notes remain until explicitly removed; conversion does not overwrite existing prose.
3. **Review by audience.** Show client-facing content and Full Scale-only content separately, with validation beside each field.
4. **Copy and hand off.** Copy individual fields or the client report, open Full Scale, and submit there. Copy CSM notes using a separate action.
5. **Record outcome.** “Copied at…” indicates handoff. Offer “Mark submitted manually” with a timestamp and an undo action. Only a future verified destination receipt permits “Submission confirmed.”

Drafts persist through popover dismissal, application restart, midnight, and loss of login or connectivity. “Temporary” means not yet submitted, not disposable.

## Field contract

| Field | Required to save | Required for a ready-to-handoff draft | Behavior |
|---|---|---|---|
| Project | No | Yes | Remember per local profile; editable; never hardcode an employer or project |
| Report date | Defaulted | Yes | Default to active shift's work date; editable for destination rules; retain after midnight |
| Send to | No | Yes | Explicit recipient chips/list; preserve spelling; validate against destination choices when available |
| What I did today | No | Non-whitespace text | Outcomes, ticket references, and open work |
| What I will do next working day | No | Non-whitespace text | Preserve “next working day”; do not silently replace with “tomorrow” |
| What I need from the client | No | Optional | Requested action and owner when known |
| What's slowing me down / growth support | No | Optional | Full Scale-only CSM note, separate from client output |
| Work notes | No | Never included automatically | Short capture inbox associated with the draft |

Account/profile setup must confirm actual project and recipient assignments rather than send to sample recipients.

Do not invent a numeric hours field: none was specified in the supplied form. Show known time information as read-only context with freshness and work date. Include hours in exported/submitted content only after confirming the destination's field and workday semantics.

## Writing guidance

Show a short collapsed “What makes a good report?” helper: be specific about work and outcomes; include ticket numbers when available; say what remains open; name blockers and the needed person/action; include nontechnical productivity blockers in the appropriate audience section; keep it factual and short.

Ticket numbers are encouraged, not mandatory. Validate required content and dates for handoff, but never block saving a partial draft. Preserve punctuation, newlines, Unicode, and pasted ticket links. Character limits remain unconfigured until verified; never silently truncate.

## Save and recovery contract

- Create a stable draft ID, schema version, local profile ID, project reference/label, work date, work timezone, recipient values, field values, work notes, revision, and creation/update timestamps. Track copy/manual completion separately from any future submission receipt.
- Default to one active draft per profile/project/work date. If one exists, open it instead of silently replacing it. Changing project/date into an existing draft offers Open existing or Keep separate; never silently merge.
- Autosave after a short pause, with a recommended 500 ms debounce; serialize writes by revision. Flush on editor close, draft switch, app deactivation, and orderly termination. A “Saved” label means that revision reached disk successfully.
- Use atomic file replacement and retain one last-known-good recovery copy. On corrupt/unreadable storage, preserve the original, explain the problem, and offer recovery/export rather than creating an empty replacement over it.
- On save failure, keep unsaved content in memory with Retry and Copy unsaved text. Do not close an editor with unsaved text without offering recovery. An abrupt process kill may lose the still-unsaved debounce window; acknowledged saved revisions must survive.
- Keep incomplete drafts until the user deletes them. Archive completed drafts rather than auto-purging. Version one has no automatic expiration. Delete with confirmation or a recoverable Recently Deleted path; settings reset affects preferences, not drafts.
- Offline editing and copy require no login. Partition drafts by an explicit local profile. If the app cannot verify the remote account, require profile selection before a handoff; do not assume the currently visible web session owns every local draft.

Storage starts with versioned Codable files under the sandbox's Application Support directory, resolved through FileManager. UserDefaults remains for small preferences. This recommendation keeps the first implementation small; see [stack and ownership](../plans/workday-companion.md#stack-and-ownership). Sandbox storage is not a claim of application-level encryption. No cloud sync or server is required.

## Audience and privacy

“Copy client report” includes project, report date, recipients, accomplishments, next-working-day plans, and client needs. It excludes CSM notes and raw work notes. The private section has its own clearly labeled Copy action and review destination. Avoid an ambiguous Copy all button.

Copy is user initiated and shows exactly which content was copied. The clipboard may be accessible to other apps or Universal Clipboard; a brief contextual note beside the private copy control makes the action understandable. Export is user initiated through a save panel, with audience choice and a preview. Diagnostics contain IDs/status only, never report bodies, recipients, cookies, or tokens.

## On-device assisted writing

The native app currently has no AI integration. Implement manual drafting, recovery, and copy first, then evaluate a field-scoped Improve action in the same delivery phase. Local drafting and handoff must work completely without AI.

Use Apple's Foundation Models on-device `SystemLanguageModel.default` through a `LanguageModelSession`. The API is available from macOS 26 and supports runtime availability checks. On-device inference can operate offline once the system model is ready. Explicitly select this local path; no automatic cloud fallback, model-server installation, or API credentials are part of this release. [Apple system-model API](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [Apple on-device overview](https://developer.apple.com/videos/play/wwdc2025/286/)

### Interaction and input boundary

Show “Improve on device” with a short explanation that the selected text is processed locally. Send only that field's text, its purpose, and concise rewriting instructions. Keep recipient metadata, unrelated fields, other drafts, and CSM notes outside client-field prompts. Use a fresh session for each request so a previous private field cannot contaminate a later client suggestion. A CSM-field request is explicit and remains within its own session.

Preserve the original and show the proposed revision before Apply. Support discard and undo. Associate each result with the input revision; if the field changes during generation, require a fresh request instead of applying an older suggestion over newer text. Cancellation, timeout, refusal, or generation failure leaves the saved draft intact.

Start with concise rewriting. Follow-up actions may shorten text, clarify a blocker, or turn user-selected work notes into accomplishment bullets. Note selection is explicit and includes an audience; it never sweeps all work notes into the prompt. Empty text offers writing guidance rather than fabricated accomplishments. Missing blocker owners or outcomes become questions for the user, not invented facts.

Preserve ticket identifiers, facts, negations, and unresolved work. Keep ticket-preservation checks deterministic and flag unexpected changes before Apply. A prompt cannot guarantee factual correctness: the review step remains required. Call the feature writing assistance, not AI validation of work performed. Give it no tools for attendance changes, external submission, or background data collection.

### Availability and resource behavior

Check model availability and language support before offering generation, and recheck after the user changes system settings. Show actionable states for ineligible devices, Apple Intelligence disabled, model not ready, unsupported language, and generation errors. Keep manual editing/copy accessible beside any explanation. Do not report that the user's Mac is ready until the check actually runs there.

Bound input to one field or an explicitly selected note set, handle the installed model's context limit without silent truncation, and allow cancellation. Permit one generation at a time; avoid background inference while the user is clocking time or editing another field. Model assets may require an initial system download; that is distinct from sending report text to a remote model. Neither prompts nor outputs enter diagnostics or automatic feedback uploads.

### AI quality and availability gate

Before enabling Improve in a release, run a small documented evaluation set of anonymized real-shaped reports: sparse notes, long fields, multiple tickets, mixed completed/unfinished work, technical and nontechnical blockers, and client/CSM separation. Record OS/model version and response latency on eligible hardware. Recheck the set after relevant model/OS updates.

All release-evaluation examples must preserve ticket IDs, completion status, and stated dependencies and introduce no unsupported accomplishments or audience leakage. Have a human review these properties; structural output checks alone do not establish them. On failure, narrow the task and reevaluate or ship manual drafts with Improve unavailable. Measure whether suggestions save editing effort; do not enable the feature solely because generation succeeds.

Test readiness/disabled states, supported/unsupported language, offline generation with a ready model, oversized input, cancellation, refusal, and changing the field during inference. Unit-test isolation, input-revision handling, and Apply/undo independently of probabilistic output. The assistant never gates draft persistence, notifications, or report handoff.

## Direct posting, later

First inspect the authenticated destination read-only: field identifiers, recipient IDs, report date, validation, authentication/CSRF, success evidence, and duplicate behavior. Prefer a supported API if one exists; otherwise evaluate a narrow WebKit-assisted fill with user review before submit. Do not invent an endpoint.

Keep the draft until a receipt matching project/work date/content is observed. A timeout after submit is “Outcome unknown”, not automatic failure: check for an existing report before any retry. Require duplicate protection or disable automatic retries. Copy remains available when the destination changes or login expires. Never silently queue report submission to happen later without a new reviewed user action.

## Acceptance scenarios

- Empty first launch offers Create draft with guidance, without requiring login.
- Saved text survives quit/relaunch, crash after acknowledged save, page refresh, and midnight.
- Rapid edits and two views of one draft cannot allow an older write to replace a newer revision.
- Disk failure and corrupt files preserve recoverable content and offer clear actions.
- Editing Friday's next-working-day plan does not assume Saturday; a manual report-date change remains intact.
- Switching profile/project/date never overwrites an unrelated draft or leaks another profile's content.
- Long text, Unicode, ticket IDs, multiline paste, and empty optional fields copy without corruption.
- Client copy/export always excludes CSM notes and raw notes; private copy requires its own action.
- Copying does not mark submitted. Manual marking is distinguishable from a verified receipt and can be undone.
- On-device Improve passes the quality/availability gate; unavailable or failed AI leaves manual drafting fully functional, with no network inference fallback.
- A generated suggestion cannot overwrite a newer field revision, alter another audience's field, or become applied/submitted without the user's action.
- Keyboard and VoiceOver users can capture, edit, review, copy, recover errors, and close without losing saved work.
